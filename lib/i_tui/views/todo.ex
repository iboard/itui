defmodule ITui.Views.Todo do
  @moduledoc """
  A todo list: the form and data layers with a screen in front of them.

  Everything it knows about a todo comes from `data/schemas/todo.json` — the
  columns it draws, the rows the form collects, the keys it stores. Nothing
  here mentions a title or a priority, so a field added to the schema file
  shows up in the list and in the form without a line of code changing.

  The schema's `columns` say which fields the table draws and in what order —
  a table reads in a different order from the form that fills it — and a field
  left out of them is shown beside the list instead, which is where a
  description and a link belong. A field marked `"form": false` is never asked
  for, which is what a serial number and a timestamp the application writes
  itself need.

  Records go through `ITui.Repo`, which keeps them in the JSON file the schema
  names as its source.

  ## Keys

    * `↑`/`↓` or `k`/`j` — move
    * `←`/`→` — sort by the column to the left, or to the right
    * `r` — the same column, the other way up
    * `a` — add, `e` or `enter` — edit
    * `space` — done, or not
    * `d` then `y` — delete
    * `R` — re-read the file
    * `esc` — back to the menu
  """

  use Atui.View

  alias Atui.{Layout, Style, Text}
  alias ITui.{Repo, Schema}
  alias ITui.Schema.{Boolean, Field, Timestamp}
  alias ITui.Views.{Form, Popup}

  # Two columns of room for the cursor, and one of air after it.
  @indent 3
  # A space, a rule, a space.
  @gap 3
  @max_column 24
  @min_flexible 16

  @impl Atui.View
  def mount(opts) do
    {schema, error} = schema(opts)

    {:ok,
     reload(%{
       schema: schema,
       notify: Keyword.get(opts, :notify),
       todos: [],
       cursor: 0,
       sort: first_sort(schema),
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
  def handle_key(:left, state), do: {:ok, sort_by(state, -1)}
  def handle_key(:right, state), do: {:ok, sort_by(state, 1)}
  def handle_key({:char, "r"}, state), do: {:ok, reverse(state)}
  def handle_key({:char, "R"}, state), do: {:ok, reload(state)}
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
    {head, rest} = rect |> Rect.inset(1) |> Layout.split_top(3)
    {list, foot} = Layout.split_bottom(rest, 2)
    # A column of air at each end: the cursor's, and one before the border.
    columns = columns(state, list.width - @indent - 1)

    Screen.new(rect.width, rect.height)
    |> Screen.box(rect, title: " #{title(state)} ", style: Style.new(fg: :bright_black))
    |> Screen.put_text(head.x + 1, head.y, summary(state), Style.new(bold: true))
    |> sorted_by(state, head)
    |> header(state, columns, %{head | y: head.y + 1})
    |> rule(state, columns, %{head | y: head.y + 2})
    |> body(state, columns, list)
    |> Screen.put_text(foot.x + 1, foot.y, detail(state, foot.width - 2), dim())
    |> Screen.put_text(foot.x + 1, foot.y + 1, keys(state, foot.width - 2), dim())
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

  # Named here as well as marked in the header, because a narrow terminal may
  # have dropped the column it is sorted by.
  defp sorted_by(screen, %{schema: nil}, _rect), do: screen
  defp sorted_by(screen, %{error: error}, _rect) when is_binary(error), do: screen
  defp sorted_by(screen, %{sort: %{by: nil}}, _rect), do: screen

  defp sorted_by(screen, state, rect) do
    case Schema.field(state.schema, state.sort.by) do
      nil ->
        screen

      field ->
        note = "sorted by " <> field.label <> marker(state, field)

        if String.length(summary(state)) + String.length(note) + 3 <= rect.width,
          do: Screen.put_text_right(screen, rect, rect.y, note, dim(), 1),
          else: screen
    end
  end

  ## Columns

  # Every column takes what its widest value needs; the first text column
  # takes whatever is left over, because that is the one with something to say.
  defp columns(%{schema: nil}, _width), do: []

  defp columns(state, width) do
    state.schema |> Schema.list_fields() |> fit(state.todos, width)
  end

  # A column that will not fit is not shown at all: half a column of dates is
  # worse than none, and the sort is named in the summary either way.
  defp fit([], _todos, _width), do: []

  defp fit(fields, todos, width) do
    widths = Enum.map(fields, &natural_width(&1, todos))
    room = width - @gap * (length(fields) - 1)
    widths = stretch(widths, flexible(fields), room - Enum.sum(widths))

    if Enum.sum(widths) > room and length(fields) > 1 do
      fit(drop_one(fields, flexible(fields)), todos, width)
    else
      place(fields, widths, width)
    end
  end

  # The column that stretches is the one with something to say, so it is the
  # last to go: what gets dropped is the rightmost of the others.
  defp drop_one(fields, nil), do: Enum.drop(fields, -1)

  defp drop_one(fields, flexible) do
    case fields |> Enum.with_index() |> Enum.reverse() |> Enum.find(&(elem(&1, 1) != flexible)) do
      nil -> Enum.drop(fields, -1)
      {_field, index} -> List.delete_at(fields, index)
    end
  end

  defp place(fields, widths, budget) do
    fields
    |> Enum.zip(widths)
    |> Enum.reduce({[], 0}, fn {field, column}, {columns, x} ->
      column = min(column, max(budget - x, 0))

      {[{field, x, column} | columns], x + column + @gap}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # A date column keeps its width whether or not there is a date in it yet, so
  # the table does not jump about when one is ticked off.
  defp natural_width(%Field{type: Timestamp} = field, _todos) do
    max(String.length(field.label) + 2, Timestamp.width())
  end

  defp natural_width(field, todos) do
    todos
    |> Enum.map(&String.length(cell(field, &1)))
    |> Enum.max(fn -> 0 end)
    |> max(String.length(Field.short(field)) + 2)
    |> min(@max_column)
  end

  defp flexible(fields), do: Enum.find_index(fields, &(&1.type == :string))

  defp stretch(widths, nil, _slack), do: widths

  defp stretch(widths, index, slack) do
    List.update_at(widths, index, &max(&1 + slack, @min_flexible))
  end

  defp header(screen, %{schema: nil}, _columns, _rect), do: screen

  defp header(screen, state, columns, rect) do
    columns
    |> Enum.reduce(screen, fn {field, x, width}, acc ->
      Screen.put_text(acc, rect.x + @indent + x, rect.y, heading(state, field, width), dim())
    end)
    |> dividers(columns, rect, "│", dim())
  end

  # A rule under the headings, meeting the box on both sides and the column
  # dividers where they cross it.
  defp rule(screen, %{schema: nil}, _columns, _rect), do: screen
  defp rule(screen, %{error: error}, _columns, _rect) when is_binary(error), do: screen

  defp rule(screen, _state, columns, rect) do
    screen
    |> Screen.put_text(rect.x - 1, rect.y, "├", border())
    |> Screen.put_text(rect.x, rect.y, String.duplicate("─", rect.width), border())
    |> Screen.put_text(rect.x + rect.width, rect.y, "┤", border())
    |> dividers(columns, rect, "┼", border())
  end

  defp dividers(screen, columns, rect, grapheme, style) do
    columns
    |> Enum.drop(-1)
    |> Enum.reduce(screen, fn {_field, x, width}, acc ->
      Screen.put(acc, rect.x + @indent + x + width + 1, rect.y, grapheme, style)
    end)
  end

  defp heading(state, field, width) do
    Screen.truncate(Field.short(field) <> marker(state, field), width)
  end

  defp marker(%{sort: %{by: key, direction: :asc}}, %{key: key}), do: " ▲"
  defp marker(%{sort: %{by: key}}, %{key: key}), do: " ▼"
  defp marker(_state, _field), do: ""

  ## The list

  defp body(screen, %{error: error}, _columns, rect) when is_binary(error) do
    error
    |> Text.wrap(max(rect.width - 2, 1))
    |> Enum.with_index(rect.y)
    |> Enum.reduce(screen, fn {line, y}, acc ->
      Screen.put_text(acc, rect.x + 1, y, line, Style.new(fg: :bright_red))
    end)
  end

  defp body(screen, %{todos: []}, _columns, rect) do
    Screen.put_text(screen, rect.x + 1, rect.y, "nothing to do yet — press a to add one", dim())
  end

  defp body(screen, state, columns, rect) do
    state.todos
    |> Enum.with_index()
    |> Enum.take(max(rect.height, 0))
    |> Enum.reduce(screen, fn {todo, index}, acc ->
      row(acc, columns, todo, %{rect | y: rect.y + index, height: 1}, index == state.cursor)
    end)
  end

  defp row(screen, columns, todo, rect, selected?) do
    style = if selected?, do: Style.new(fg: :black, bg: :bright_cyan)

    screen
    |> Screen.fill(rect, " ", style)
    |> Screen.put_text(rect.x + 1, rect.y, if(selected?, do: "▸", else: " "), style)
    |> dividers(columns, rect, "│", style || dim())
    |> cells(columns, todo, rect, style)
  end

  defp cells(screen, columns, todo, rect, style) do
    Enum.reduce(columns, screen, fn {field, x, width}, acc ->
      text = Screen.truncate(cell(field, todo), width)
      x = rect.x + @indent + x + offset(field, text, width)

      Screen.put_text(acc, x, rect.y, text, style || value_style(field, todo))
    end)
  end

  # A number reads as a column when it ends where the others end.
  defp offset(%Field{type: :integer}, text, width), do: max(width - String.length(text), 0)
  defp offset(_field, _text, _width), do: 0

  # A todo that is done is not gone, but it should stop shouting.
  defp value_style(%Field{type: :string}, todo), do: if(done?(todo), do: dim())
  defp value_style(_field, _todo), do: nil

  defp cell(%Field{type: Boolean} = field, todo) do
    if todo[field.key] == true, do: "[x]", else: "[ ]"
  end

  defp cell(field, todo), do: field |> Field.format(todo[field.key]) |> one_line()

  ## What does not fit in a column

  defp detail(%{schema: nil}, _width), do: ""

  defp detail(%{confirming: id} = state, width) when not is_nil(id) do
    title = state.todos |> Enum.find(&(&1[:id] == id)) |> Kernel.||(%{}) |> Map.get(:title, "")

    Screen.truncate(~s(delete "#{title}"? y / n), width)
  end

  defp detail(state, width) do
    case current(state) do
      nil ->
        ""

      todo ->
        state.schema
        |> Schema.detail_fields()
        |> Enum.map(fn field -> {field, one_line(Field.format(field, todo[field.key]))} end)
        |> Enum.reject(fn {_field, value} -> value == "" end)
        |> Enum.map_join(" · ", fn {field, value} -> "#{field.label}: #{value}" end)
        |> Screen.truncate(width)
    end
  end

  # A field of several lines has to say what it says in one, down here.
  defp one_line(value), do: value |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp keys(%{error: error}, _width) when is_binary(error), do: "esc back"

  defp keys(_state, width) do
    Text.first_fitting(
      [
        "a add · enter edit · space done · d delete · ←→ sort · r reverse · esc back",
        "a add · enter edit · space done · d delete · ←→ sort · esc back",
        "a · enter · space · d · ←→ · esc"
      ],
      width
    )
  end

  ## Sorting

  defp first_sort(nil), do: %{by: nil, direction: :asc}

  defp first_sort(schema) do
    case Schema.list_fields(schema) do
      [] -> %{by: nil, direction: :asc}
      [first | _rest] -> %{by: schema.sort || first.key, direction: :asc}
    end
  end

  defp sort_by(%{schema: nil} = state, _by), do: state

  defp sort_by(state, by) do
    fields = Schema.list_fields(state.schema)

    case Enum.find_index(fields, &(&1.key == state.sort.by)) do
      nil ->
        state

      index ->
        field = Enum.at(fields, Integer.mod(index + by, length(fields)))

        resort(%{state | sort: %{state.sort | by: field.key}})
    end
  end

  defp reverse(state) do
    resort(%{state | sort: %{state.sort | direction: other(state.sort.direction)}})
  end

  defp other(:asc), do: :desc
  defp other(:desc), do: :asc

  # The cursor follows the todo it was on, rather than the place it was in.
  defp resort(state) do
    todos = sorted(state, state.todos)
    cursor = Enum.find_index(todos, &(&1 == current(state))) || state.cursor

    %{state | todos: todos, cursor: clamp(cursor, todos)}
  end

  defp sorted(%{sort: %{by: nil}}, todos), do: todos

  defp sorted(state, todos) do
    case Schema.field(state.schema, state.sort.by) do
      nil -> todos
      field -> Enum.sort(todos, &before?(key(field, &1), key(field, &2), state.sort.direction))
    end
  end

  defp key(%Field{type: :string} = field, todo) do
    case todo[field.key] do
      value when is_binary(value) -> String.downcase(value)
      value -> value
    end
  end

  defp key(field, todo), do: todo[field.key]

  # Whichever way up the column is, a todo that has no value for it goes last:
  # an empty cell is not a small one.
  defp before?(nil, nil, _direction), do: true
  defp before?(nil, _second, _direction), do: false
  defp before?(_first, nil, _direction), do: true
  defp before?(first, second, :asc), do: first <= second
  defp before?(first, second, :desc), do: first >= second

  ## Changing things

  defp add(%{schema: nil} = state), do: {:ok, state}

  defp add(state) do
    {:push, Form, form_opts(state, "New #{item_label(state)}", %{}), %{state | editing: :new}}
  end

  defp edit(state, nil), do: {:ok, state}

  defp edit(state, todo) do
    {:push, Form, form_opts(state, "Edit #{item_label(state)}", todo),
     %{state | editing: todo[:id]}}
  end

  defp form_opts(state, title, values) do
    [schema: state.schema, title: title, values: values, notify: __MODULE__]
  end

  defp save(%{editing: :new} = state, attrs) do
    state.schema |> Repo.insert(params(state, attrs, nil)) |> handled(state)
  end

  defp save(%{editing: id} = state, attrs) when is_integer(id) do
    previous = Enum.find(state.todos, &(&1[:id] == id))

    state.schema |> Repo.update(id, params(state, attrs, previous)) |> handled(state)
  end

  defp save(state, _attrs), do: state

  defp toggle(state, nil), do: state

  defp toggle(state, todo) do
    params = params(state, %{done: not done?(todo)}, todo)

    state.schema |> Repo.update(todo[:id], params) |> handled(state)
  end

  # The repository casts parameters, which are named the way a form names them.
  defp params(state, attrs, previous) do
    attrs
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> checked_off(state, previous)
  end

  # "Checked off" is the moment the tick went in, so it is written when the
  # tick changes and taken away again when it is unticked.
  defp checked_off(params, state, previous) do
    done = params["done"]

    cond do
      is_nil(Schema.field(state.schema, :done_at)) -> params
      is_nil(done) or done == (previous && done?(previous)) -> params
      done -> Map.put(params, "done_at", Timestamp.now())
      true -> Map.put(params, "done_at", nil)
    end
  end

  defp delete(state, id) do
    state.schema |> Repo.delete(id) |> handled(state)
  end

  defp confirm(state, nil), do: state
  defp confirm(state, todo), do: %{state | confirming: todo[:id]}

  defp handled(:ok, state), do: reload(state)
  defp handled({:ok, _record}, state), do: reload(state)
  defp handled({:error, reason}, state), do: %{state | error: message(state, reason)}

  defp message(_state, reason) when is_binary(reason), do: reason

  defp message(state, %Ecto.Changeset{} = changeset) do
    state.schema
    |> Schema.errors(changeset)
    |> Enum.map_join("; ", fn {field, message} -> "#{field.label} #{message}" end)
  end

  defp reload(%{schema: nil} = state), do: state

  defp reload(state) do
    case Repo.all(state.schema) do
      {:ok, todos} ->
        todos = sorted(state, todos)

        %{state | todos: todos, error: nil, cursor: clamp(state.cursor, todos)}

      {:error, reason} ->
        %{state | error: message(state, reason)}
    end
  end

  defp current(state), do: Enum.at(state.todos, state.cursor)

  defp done?(todo), do: todo[:done] == true

  defp move(state, by) do
    case length(state.todos) do
      0 -> state
      count -> %{state | cursor: Integer.mod(state.cursor + by, count)}
    end
  end

  defp clamp(cursor, todos), do: cursor |> min(max(length(todos) - 1, 0)) |> max(0)

  defp border, do: Style.new(fg: :bright_black)

  defp dim, do: Style.new(dim: true)
end
