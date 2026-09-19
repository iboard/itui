defmodule ITui.Views.Todo do
  @moduledoc """
  A todo list: the form and data layers with a screen in front of them.

  Everything it knows about a todo comes from `data/schemas/todo.json` — the
  columns it draws, the rows the form collects, the keys it stores. Nothing
  here mentions a title or a priority, so a field added to the schema file
  shows up in the list and in the form without a line of code changing.

  Records go through `ITui.Repo`, which keeps them in the JSON file the schema
  names as its source.

  ## Keys

    * `↑`/`↓` or `k`/`j` — move
    * `a` — add, `e` or `enter` — edit
    * `space` — done, or not
    * `d` then `y` — delete
    * `r` — re-read the file
    * `esc` — back to the menu
  """

  use Atui.View

  alias Atui.{Layout, Style, Text}
  alias ITui.{Repo, Schema}
  alias ITui.Schema.Field
  alias ITui.Views.{Form, Popup}

  @impl Atui.View
  def mount(opts) do
    {schema, error} = schema(opts)

    {:ok,
     reload(%{
       schema: schema,
       notify: Keyword.get(opts, :notify),
       todos: [],
       cursor: 0,
       editing: nil,
       confirming: nil,
       error: error
     })}
  end

  # The form owns the keyboard while it is open, the same way the menu gives
  # way to this view — nothing else here may claim a letter it is typing.
  @impl Atui.View
  def handle_key(_key, %{editing: editing} = state) when not is_nil(editing) do
    {:pass, state}
  end

  def handle_key(:esc, %{confirming: id} = state) when not is_nil(id) do
    {:ok, %{state | confirming: nil}}
  end

  def handle_key({:char, "y"}, %{confirming: id} = state) when not is_nil(id) do
    {:ok, state |> delete(id) |> Map.put(:confirming, nil)}
  end

  def handle_key(_key, %{confirming: id} = state) when not is_nil(id) do
    {:ok, %{state | confirming: nil}}
  end

  def handle_key(:esc, state), do: {:pop, state}

  def handle_key(key, state) when key in [:up, {:char, "k"}], do: {:ok, move(state, -1)}
  def handle_key(key, state) when key in [:down, {:char, "j"}], do: {:ok, move(state, 1)}
  def handle_key({:char, "r"}, state), do: {:ok, reload(state)}
  def handle_key({:char, "a"}, state), do: add(state)

  def handle_key(key, state) when key in [:enter, {:char, "e"}] do
    edit(state, current(state))
  end

  def handle_key({:char, " "}, state), do: {:ok, toggle(state, current(state))}
  def handle_key({:char, "d"}, state), do: {:ok, confirm(state, current(state))}
  def handle_key(_key, state), do: {:pass, state}

  @impl Atui.View
  def handle_event({:popup_closed, Form, {:submitted, attrs}}, state) do
    {:ok, state |> save(attrs) |> Map.put(:editing, nil)}
  end

  def handle_event({:popup_closed, Form, _result}, state), do: {:ok, %{state | editing: nil}}
  def handle_event(_event, state), do: {:ok, state}

  @impl Atui.View
  def render(state, rect) do
    {header, rest} = rect |> Rect.inset(1) |> Layout.split_top(2)
    {list, footer} = Layout.split_bottom(rest, 1)

    Screen.new(rect.width, rect.height)
    |> Screen.box(rect, title: " #{title(state)} ", style: Style.new(fg: :bright_black))
    |> Screen.put_text(header.x + 1, header.y, summary(state), Style.new(bold: true))
    |> body(state, list)
    |> Screen.put_text(footer.x + 1, footer.y, footer(state, footer.width - 2), dim())
  end

  @impl Atui.View
  def unmount(state), do: Popup.closed(state.notify, __MODULE__, :ok)

  defp schema(opts) do
    case Keyword.fetch(opts, :schema) do
      {:ok, %Schema{} = schema} ->
        {schema, nil}

      :error ->
        case Schema.load(Keyword.get(opts, :schema_name, "todo")) do
          {:ok, schema} -> {schema, nil}
          {:error, reason} -> {nil, reason}
        end
    end
  end

  defp title(%{schema: nil}), do: "Todo"
  defp title(%{schema: schema}), do: schema.title

  defp item_label(%{schema: nil}), do: "todo"
  defp item_label(%{schema: schema}), do: String.downcase(schema.label)

  defp summary(%{error: error}) when is_binary(error), do: "nothing to show"

  defp summary(state) do
    done = Enum.count(state.todos, &done?/1)

    "#{length(state.todos)} #{plural(length(state.todos))}, #{done} done"
  end

  defp plural(1), do: "todo"
  defp plural(_count), do: "todos"

  defp body(screen, %{error: error}, rect) when is_binary(error) do
    error
    |> Text.wrap(max(rect.width - 2, 1))
    |> Enum.with_index(rect.y)
    |> Enum.reduce(screen, fn {line, y}, acc ->
      Screen.put_text(acc, rect.x + 1, y, line, Style.new(fg: :bright_red))
    end)
  end

  defp body(screen, %{todos: []}, rect) do
    Screen.put_text(screen, rect.x + 1, rect.y, "nothing to do yet — press a to add one", dim())
  end

  defp body(screen, state, rect) do
    state.todos
    |> Enum.with_index()
    |> Enum.take(max(rect.height, 0))
    |> Enum.reduce(screen, fn {todo, index}, acc ->
      row(acc, state, todo, %{rect | y: rect.y + index, height: 1}, index == state.cursor)
    end)
  end

  defp row(screen, state, todo, rect, selected?) do
    style = if selected?, do: Style.new(fg: :black, bg: :bright_cyan)
    marker = if selected?, do: "▸ ", else: "  "
    box = if done?(todo), do: "[x] ", else: "[ ] "
    title = Screen.truncate(to_string(todo["title"]), max(rect.width - 12, 1))

    screen
    |> Screen.fill(rect, " ", style)
    |> Screen.put_text(rect.x + 1, rect.y, marker <> box <> title, title_style(todo, style))
    |> Screen.put_text_right(rect, rect.y, extra(state, todo), style || dim(), 2)
  end

  # A todo that is done is not gone, but it should stop shouting.
  defp title_style(todo, nil), do: if(done?(todo), do: dim())
  defp title_style(_todo, style), do: style

  # Whatever the schema declares beyond the two columns the list draws itself.
  defp extra(%{schema: schema}, todo) do
    schema.fields
    |> Enum.reject(&(&1.name in ["title", "done"]))
    |> Enum.map_join("  ", fn field ->
      "#{field.label}: #{Field.format(field, todo[field.name])}"
    end)
  end

  defp footer(%{confirming: id} = state, width) when not is_nil(id) do
    title = state.todos |> Enum.find(&(&1["id"] == id)) |> Kernel.||(%{}) |> Map.get("title", "")

    Screen.truncate(~s(delete "#{title}"? y / n), width)
  end

  defp footer(%{error: error}, _width) when is_binary(error), do: "esc back"

  defp footer(_state, width) do
    Text.first_fitting(
      [
        "a add · enter edit · space done · d delete · r reload · esc back",
        "a add · enter edit · space done · d delete · esc back",
        "a · enter · space · d · esc"
      ],
      width
    )
  end

  defp add(%{schema: nil} = state), do: {:ok, state}

  defp add(state) do
    {:push, Form, form_opts(state, "New #{item_label(state)}", %{}), %{state | editing: :new}}
  end

  defp edit(state, nil), do: {:ok, state}

  defp edit(state, todo) do
    {:push, Form, form_opts(state, "Edit #{item_label(state)}", todo),
     %{state | editing: todo["id"]}}
  end

  defp form_opts(state, title, values) do
    [schema: state.schema, title: title, values: values, notify: __MODULE__]
  end

  defp save(%{editing: :new} = state, attrs) do
    state.schema |> Repo.insert(attrs) |> handled(state)
  end

  defp save(%{editing: id} = state, attrs) when is_integer(id) do
    state.schema |> Repo.update(id, attrs) |> handled(state)
  end

  defp save(state, _attrs), do: state

  defp toggle(state, nil), do: state

  defp toggle(state, todo) do
    state.schema |> Repo.update(todo["id"], %{"done" => not done?(todo)}) |> handled(state)
  end

  defp delete(state, id) do
    state.schema |> Repo.delete(id) |> handled(state)
  end

  defp confirm(state, nil), do: state
  defp confirm(state, todo), do: %{state | confirming: todo["id"]}

  defp handled(:ok, state), do: reload(state)
  defp handled({:ok, _record}, state), do: reload(state)
  defp handled({:error, reason}, state), do: %{state | error: message(reason)}

  defp message(reason) when is_binary(reason), do: reason

  defp message(errors) when is_list(errors) do
    Enum.map_join(errors, "; ", fn {name, message} -> "#{name} #{message}" end)
  end

  defp reload(%{schema: nil} = state), do: state

  defp reload(state) do
    case Repo.all(state.schema) do
      {:ok, todos} -> %{state | todos: todos, error: nil, cursor: clamp(state.cursor, todos)}
      {:error, reason} -> %{state | error: message(reason)}
    end
  end

  defp current(state), do: Enum.at(state.todos, state.cursor)

  defp done?(todo), do: todo["done"] == true

  defp move(state, by) do
    case length(state.todos) do
      0 -> state
      count -> %{state | cursor: Integer.mod(state.cursor + by, count)}
    end
  end

  defp clamp(cursor, todos), do: cursor |> min(max(length(todos) - 1, 0)) |> max(0)

  defp dim, do: Style.new(dim: true)
end
