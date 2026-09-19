defmodule ITui.Views.Form do
  @moduledoc """
  A form over an `ITui.Schema`: one row per field, and what came out of it.

  Pushed by whatever needs values — the menu, to collect the arguments of a
  command; the todo list, to add or edit an entry — and popped with the answer.
  The view that pushed it gets one message on the way out
  (`ITui.Views.Popup`), carrying `{:submitted, attrs}` or `:cancelled`.

  Text fields are `Atui.TextInput`s and take the editing keys a readline user
  expects. A boolean field is a toggle instead, flipped with space, because a
  yes/no question deserves less than a text field.

  Nothing is submitted until every field casts: `enter` shows all of the
  mistakes at once and stays open, so a form is never half-accepted. A field
  the schema marks `"form": false` is not asked for and not answered for —
  a timestamp the application writes itself is nobody's to type.

  ## Keys

    * `tab`, `↓` / `shift-tab`, `↑` — the next field, the previous one
    * `space` — flip the toggle the cursor is on
    * `enter` — save
    * `esc` — cancel
  """

  use Atui.View

  alias Atui.{Layout, Style, Text, TextInput}
  alias ITui.Schema
  alias ITui.Schema.{Boolean, Field}
  alias ITui.Views.Popup

  @label_width 20

  @impl Atui.View
  def mount(opts) do
    schema = Keyword.fetch!(opts, :schema)
    values = Keyword.get(opts, :values, %{})

    {:ok,
     %{
       schema: schema,
       title: Keyword.get(opts, :title, schema.label),
       notify: Keyword.get(opts, :notify),
       widgets: schema |> Schema.form_fields() |> Enum.map(&widget(&1, values)),
       focus: 0,
       errors: [],
       result: :cancelled
     }}
  end

  @impl Atui.View
  def place(state, viewport) do
    Rect.centered(
      viewport,
      clamp(label_width(state) + 48, 44, viewport.width - 4),
      clamp(length(state.widgets) + length(state.errors) + 5, 8, viewport.height - 2)
    )
  end

  @impl Atui.View
  def handle_key(:esc, state), do: {:pop, %{state | result: :cancelled}}
  def handle_key(:enter, state), do: submit(state)

  def handle_key(key, state) when key in [:tab, :down], do: {:ok, focus(state, 1)}
  def handle_key(key, state) when key in [{[:shift], :tab}, :up], do: {:ok, focus(state, -1)}

  def handle_key(key, state) do
    case focused(state) do
      %{input: nil} = widget -> toggle(state, widget, key)
      %{input: input} = widget -> edit(state, widget, input, key)
      nil -> {:pass, state}
    end
  end

  @impl Atui.View
  def render(state, rect) do
    {body, footer} = rect |> Rect.inset(1) |> Layout.split_bottom(1)
    {rows, messages} = Layout.split_top(body, length(state.widgets))

    state.widgets
    |> Enum.with_index()
    |> Enum.reduce(blank(state, rect), fn {widget, index}, screen ->
      row(screen, state, widget, index, %{rows | y: rows.y + index, height: 1})
    end)
    |> errors(state, messages)
    |> Screen.put_text(footer.x + 1, footer.y, keys(footer.width - 2), dim())
  end

  @impl Atui.View
  def unmount(state), do: Popup.closed(state.notify, __MODULE__, state.result)

  defp blank(state, rect) do
    Screen.new(rect.width, rect.height)
    |> Screen.box(rect, title: " #{state.title} ", style: Style.new(fg: :bright_black))
  end

  defp widget(%Field{type: Boolean} = field, values) do
    %{field: field, input: nil, checked: starting_value(field, values) == true}
  end

  defp widget(%Field{} = field, values) do
    value = Field.format(field, starting_value(field, values))

    %{
      field: field,
      input: TextInput.new(value: value, placeholder: field.placeholder || ""),
      checked: nil
    }
  end

  defp starting_value(field, values), do: Map.get(values, field.key, Field.default(field))

  defp row(screen, state, widget, index, rect) do
    focused? = index == state.focus
    width = label_width(state)
    label = Screen.truncate(label(widget.field), width)

    screen
    |> Screen.put_text(rect.x + 1, rect.y, label, label_style(focused?))
    |> value(widget, %{rect | x: rect.x + width + 4, width: rect.width - width - 5}, focused?)
  end

  defp value(screen, %{input: nil} = widget, rect, focused?) do
    box = if widget.checked, do: "[x] yes", else: "[ ] no"

    Screen.put_text(screen, rect.x, rect.y, box, if(focused?, do: focus_style()))
  end

  defp value(screen, %{input: input}, rect, focused?) do
    TextInput.draw(screen, input, rect,
      focus: focused?,
      placeholder_style: dim(),
      style: if(focused?, do: focus_style())
    )
  end

  defp errors(screen, %{errors: []}, _rect), do: screen

  defp errors(screen, state, rect) do
    state.errors
    |> Enum.map(fn {field, message} -> "#{field.label} #{message}" end)
    |> Enum.take(max(rect.height - 1, 0))
    |> Enum.with_index(rect.y + 1)
    |> Enum.reduce(screen, fn {message, y}, acc ->
      Screen.put_text(acc, rect.x + 1, y, Screen.truncate(message, rect.width - 2), error_style())
    end)
  end

  defp keys(width) do
    Text.first_fitting(
      ["tab next · space toggle · enter save · esc cancel", "tab · enter save · esc"],
      width
    )
  end

  # Only the fields that were drawn are cast, and only they come back: a
  # schema keeps some things to itself, and a form must not answer for them.
  defp submit(state) do
    shown = Enum.map(state.widgets, & &1.field)

    case Schema.cast(state.schema, params(state), Enum.map(shown, & &1.name)) do
      {:ok, attrs} ->
        {:pop, %{state | result: {:submitted, Map.take(attrs, Enum.map(shown, & &1.key))}}}

      {:error, changeset} ->
        errors = Schema.errors(state.schema, changeset)

        {:ok, %{state | errors: errors, focus: focus_of(state, errors)}}
    end
  end

  defp params(state) do
    Map.new(state.widgets, fn
      %{field: field, input: nil, checked: checked} -> {field.name, checked}
      %{field: field, input: input} -> {field.name, TextInput.value(input)}
    end)
  end

  defp toggle(state, widget, {:char, " "}) do
    {:ok, put_widget(state, %{widget | checked: not widget.checked})}
  end

  defp toggle(state, _widget, _key), do: {:pass, state}

  defp edit(state, widget, input, key) do
    case TextInput.handle_key(input, key) do
      {:ok, input} -> {:ok, put_widget(state, %{widget | input: input})}
      {:pass, _input} -> {:pass, state}
    end
  end

  defp put_widget(state, widget) do
    %{state | widgets: List.replace_at(state.widgets, state.focus, widget)}
  end

  defp focused(state), do: Enum.at(state.widgets, state.focus)

  defp focus(state, by) do
    case length(state.widgets) do
      0 -> state
      count -> %{state | focus: Integer.mod(state.focus + by, count)}
    end
  end

  # The cursor lands on the first field that was wrong, which is where the
  # person has to go anyway.
  defp focus_of(state, [{field, _message} | _rest]) do
    Enum.find_index(state.widgets, &(&1.field.key == field.key)) || state.focus
  end

  defp focus_of(state, _errors), do: state.focus

  # The required marker is part of the label as far as the columns care.
  defp label_width(state) do
    state.widgets
    |> Enum.map(&String.length(label(&1.field)))
    |> Enum.max(fn -> 0 end)
    |> min(@label_width)
    |> max(6)
  end

  defp label(%Field{required: true} = field), do: field.label <> " *"
  defp label(%Field{} = field), do: field.label

  defp label_style(true), do: Style.new(bold: true)
  defp label_style(false), do: dim()

  defp focus_style, do: Style.new(fg: :bright_cyan)
  defp error_style, do: Style.new(fg: :bright_red)
  defp dim, do: Style.new(dim: true)

  defp clamp(value, low, high), do: value |> max(low) |> min(max(high, low))
end
