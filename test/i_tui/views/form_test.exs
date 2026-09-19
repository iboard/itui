defmodule ITui.Views.FormTest do
  use ITui.UICase, async: false

  alias ITui.Schema
  alias ITui.Views.Form

  @schema """
  {"name": "todo", "label": "Todo", "fields": [
    {"name": "title", "label": "Title", "required": true, "placeholder": "what to do"},
    {"name": "priority", "label": "Priority", "type": "integer", "default": 2},
    {"name": "done", "label": "Done", "type": "boolean", "default": false}
  ]}
  """

  @multiline """
  {"name": "note", "label": "Note", "fields": [
    {"name": "title", "label": "Title", "required": true},
    {"name": "body", "label": "Body", "lines": 3, "placeholder": "say something"}
  ]}
  """

  setup do
    {:ok, schema} = Schema.parse(@schema)

    %{schema: schema}
  end

  defp start_form(schema, opts \\ []) do
    start_ui(Form, Keyword.merge([schema: schema, size: {70, 16}], opts))
  end

  defp result(ui), do: Runtime.view_state(ui, Form).result

  test "draws a row per field, with the defaults already in them", %{schema: schema} do
    screen = schema |> start_form() |> text()

    assert screen =~ "Todo"
    assert screen =~ "Title *"
    assert screen =~ "what to do"
    assert screen =~ "Priority"
    assert screen =~ "2"
    assert screen =~ "Done"
    assert screen =~ "[ ] no"
    assert screen =~ "enter save"
  end

  test "starts from the values it was given", %{schema: schema} do
    values = %{title: "Write it", priority: 1, done: true}
    screen = schema |> start_form(values: values, title: "Edit todo") |> text()

    assert screen =~ "Edit todo"
    assert screen =~ "Write it"
    assert screen =~ "[x] yes"
  end

  test "types into the focused field, and tab moves on", %{schema: schema} do
    ui = start_form(schema)

    assert type(ui, "Write it") =~ "Write it"

    press(ui, [:tab, :end, {:char, "7"}])
    assert text(ui) =~ "27"

    assert press(ui, [:tab, {:char, " "}]) =~ "[x] yes"
    assert press(ui, [{:char, " "}]) =~ "[ ] no"
  end

  test "shift-tab and the arrows move between fields too", %{schema: schema} do
    ui = start_form(schema)

    press(ui, [{[:shift], :tab}, {:char, " "}])
    assert text(ui) =~ "[x] yes"

    press(ui, [:up, :up, {:char, "x"}])
    assert text(ui) =~ "Title *    x"
  end

  test "enter submits what was cast", %{schema: schema} do
    ui = start_form(schema)

    type(ui, "Write it")
    press(ui, [:tab, :home, :delete, {:char, "1"}, :tab, {:char, " "}, :enter])

    assert result(ui) == {:submitted, %{title: "Write it", priority: 1, done: true}}
  end

  test "enter with a mistake in it stays open and says what is wrong", %{schema: schema} do
    ui = start_form(schema)

    press(ui, [:tab, :end])
    type(ui, "x")
    screen = press(ui, :enter)

    assert screen =~ "Title is required"
    assert screen =~ "Priority must be a whole number"
    assert result(ui) == :cancelled

    # The cursor lands on the first field that was wrong.
    assert Runtime.view_state(ui, Form).focus == 0
  end

  test "esc cancels", %{schema: schema} do
    ui = start_form(schema)

    type(ui, "Write it")
    press(ui, :esc)

    assert result(ui) == :cancelled
  end

  describe "a field of several lines" do
    setup do
      {:ok, schema} = Schema.parse(@multiline)

      %{ui: start_ui(Form, schema: schema, size: {70, 16})}
    end

    test "is drawn over as many rows as the schema gives it", %{ui: ui} do
      screen = text(ui)

      assert screen =~ "Body"
      assert screen =~ "say something"
      assert screen =~ "enter save"

      press(ui, :tab)
      assert text(ui) =~ "ctrl-d save"
    end

    test "enter starts a new line instead of saving", %{ui: ui} do
      press(ui, :tab)
      type(ui, "one")
      press(ui, :enter)
      screen = type(ui, "two")

      assert screen =~ "one"
      assert screen =~ "two"
      assert result(ui) == :cancelled
      assert Runtime.view_stack(ui) == [Form]
    end

    test "ctrl-d saves from inside it", %{ui: ui} do
      type(ui, "A note")
      press(ui, :tab)
      type(ui, "first")
      press(ui, :enter)
      type(ui, "second")
      press(ui, {[:ctrl], "d"})

      assert result(ui) == {:submitted, %{title: "A note", body: "first\nsecond"}}
    end

    test "the arrows walk within it, and out of it at its edges", %{ui: ui} do
      press(ui, :tab)
      type(ui, "one")
      press(ui, :enter)
      type(ui, "two")

      # Up once stays inside the field, twice leaves it.
      press(ui, :up)
      assert Runtime.view_state(ui, Form).focus == 1

      press(ui, :up)
      assert Runtime.view_state(ui, Form).focus == 0
    end

    test "enter on a single-line field still saves", %{ui: ui} do
      type(ui, "A note")
      press(ui, :enter)

      assert result(ui) == {:submitted, %{title: "A note", body: ""}}
    end
  end

  test "a form with no fields is still a form", %{schema: _schema} do
    {:ok, schema} = Schema.parse(~s({"name": "empty", "fields": []}))
    ui = start_form(schema)

    assert press(ui, [:tab, :down, :up]) =~ "Empty"
    press(ui, :enter)
    assert result(ui) == {:submitted, %{}}
  end
end
