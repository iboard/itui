defmodule ITui.Views.TodoTest do
  use ITui.UICase, async: false

  alias ITui.{Repo, Schema}
  alias ITui.Views.{Form, Todo}

  @schema """
  {"name": "todo", "label": "Todo", "title": "Todos", "fields": [
    {"name": "title", "label": "Title", "required": true, "placeholder": "what to do"},
    {"name": "priority", "label": "Priority", "type": "integer", "default": 2},
    {"name": "done", "label": "Done", "type": "boolean", "default": false}
  ]}
  """

  setup do
    source = Path.join(System.tmp_dir!(), "i_tui_#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(source) end)

    {:ok, schema} = Schema.parse(@schema)
    schema = %{schema | source: source}

    %{schema: schema, source: source, ui: start_ui(Todo, schema: schema, size: {70, 14})}
  end

  defp add(ui, title) do
    press(ui, {:char, "a"})
    type(ui, title)
    press(ui, :enter)

    settle(ui)
  end

  test "an empty list says how to fill it", %{ui: ui} do
    screen = text(ui)

    assert screen =~ "Todos"
    assert screen =~ "0 todos, 0 done"
    assert screen =~ "nothing to do yet — press a to add one"
  end

  test "a adds one through the form, and it lands on disk", %{ui: ui, schema: schema} do
    assert press(ui, {:char, "a"}) =~ "New todo"
    assert Runtime.view_stack(ui) == [Form, Todo]
    press(ui, :esc)

    screen = add(ui, "Write the docs")

    assert Runtime.view_stack(ui) == [Todo]
    assert screen =~ "▸ [ ] Write the docs"
    assert screen =~ "Priority: 2"
    assert screen =~ "1 todo, 0 done"

    assert {:ok, [%{title: "Write the docs", priority: 2, done: false}]} =
             Repo.all(schema)
  end

  test "a form that was cancelled changes nothing", %{ui: ui, schema: schema} do
    press(ui, {:char, "a"})
    type(ui, "Never mind")
    press(ui, :esc)
    screen = settle(ui)

    assert Runtime.view_stack(ui) == [Todo]
    assert screen =~ "nothing to do yet"
    assert Repo.all(schema) == {:ok, []}
  end

  test "space marks one done, and again marks it not done", %{ui: ui, schema: schema} do
    add(ui, "Write the docs")

    assert press(ui, {:char, " "}) =~ "▸ [x] Write the docs"
    assert text(ui) =~ "1 todo, 1 done"
    assert {:ok, [%{done: true}]} = Repo.all(schema)

    assert press(ui, {:char, " "}) =~ "▸ [ ] Write the docs"
    assert {:ok, [%{done: false}]} = Repo.all(schema)
  end

  test "enter edits the one under the cursor", %{ui: ui, schema: schema} do
    add(ui, "Write the docs")

    screen = press(ui, :enter)
    assert screen =~ "Edit todo"
    assert screen =~ "Write the docs"

    press(ui, [:end, {:char, "!"}, :enter])

    assert settle(ui) =~ "Write the docs!"
    assert {:ok, [%{title: "Write the docs!", id: 1}]} = Repo.all(schema)
  end

  test "the arrows move the cursor through the list", %{ui: ui} do
    add(ui, "First")
    add(ui, "Second")

    assert text(ui) =~ "▸ [ ] First"
    assert press(ui, :down) =~ "▸ [ ] Second"
    assert press(ui, :down) =~ "▸ [ ] First"
    assert press(ui, {:char, "j"}) =~ "▸ [ ] Second"
  end

  test "d asks before deleting, and n keeps it", %{ui: ui, schema: schema} do
    add(ui, "Write the docs")

    assert press(ui, {:char, "d"}) =~ ~s(delete "Write the docs"? y / n)

    assert press(ui, {:char, "n"}) =~ "Write the docs"
    assert {:ok, [_todo]} = Repo.all(schema)
  end

  test "d then y deletes it", %{ui: ui, schema: schema} do
    add(ui, "Write the docs")
    add(ui, "And the tests")

    press(ui, {:char, "d"})
    screen = press(ui, {:char, "y"})

    refute screen =~ "Write the docs"
    assert screen =~ "And the tests"
    assert {:ok, [%{title: "And the tests"}]} = Repo.all(schema)
  end

  test "the cursor stays inside the list after a delete", %{ui: ui} do
    add(ui, "Only one")

    press(ui, [{:char, "d"}, {:char, "y"}])

    assert text(ui) =~ "nothing to do yet"
    assert Runtime.view_state(ui, Todo).cursor == 0
  end

  test "r re-reads the file", %{ui: ui, schema: schema} do
    {:ok, _record} = Repo.insert(schema, %{"title" => "Added behind its back"})

    refute text(ui) =~ "Added behind its back"
    assert press(ui, {:char, "r"}) =~ "Added behind its back"
  end
end

defmodule ITui.Views.TodoErrorTest do
  use ITui.UICase, async: false

  alias ITui.Schema
  alias ITui.Views.Todo

  test "a schema it could not read is reported, not fatal" do
    ui = start_ui(Todo, schema_name: "nonexistent", size: {70, 14})
    screen = text(ui)

    assert screen =~ "no such file or directory"
    assert screen =~ "nothing to show"
  end

  test "a schema with nowhere to keep records is reported too" do
    {:ok, schema} = Schema.parse(~s({"name": "todo", "fields": [{"name": "title"}]}))
    ui = start_ui(Todo, schema: schema, size: {70, 14})

    assert text(ui) =~ "has no source to read records from"
  end
end
