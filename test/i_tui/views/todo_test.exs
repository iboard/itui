defmodule ITui.Views.TodoTest do
  use ITui.UICase, async: false

  alias ITui.{Repo, Schema}
  alias ITui.Views.{Form, Todo}

  @schema """
  {"name": "todo", "label": "Todo", "title": "Todos", "sort": "inserted_at", "fields": [
    {"name": "title", "label": "Title", "required": true, "placeholder": "what to do"},
    {"name": "description", "label": "Description", "list": false},
    {"name": "priority", "label": "Priority", "type": "integer", "default": 2},
    {"name": "done", "label": "Done", "type": "boolean", "default": false},
    {"name": "inserted_at", "label": "Created", "type": "datetime", "form": false},
    {"name": "done_at", "label": "Checked off", "type": "datetime", "form": false}
  ]}
  """

  setup do
    source = Path.join(System.tmp_dir!(), "i_tui_#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(source) end)

    {:ok, schema} = Schema.parse(@schema)
    schema = %{schema | source: source}

    %{schema: schema, source: source, ui: start_ui(Todo, schema: schema, size: {88, 16})}
  end

  defp add(ui, title) do
    press(ui, {:char, "a"})
    type(ui, title)
    press(ui, :enter)

    settle(ui)
  end

  defp row(screen, title) do
    screen |> String.split("\r\n") |> Enum.find("", &(&1 =~ title))
  end

  defp titles(ui) do
    ui |> Runtime.view_state(Todo) |> Map.fetch!(:todos) |> Enum.map(& &1[:title])
  end

  defp one(schema), do: schema |> Repo.all() |> elem(1) |> hd()

  test "an empty list says how to fill it", %{ui: ui} do
    screen = text(ui)

    assert screen =~ "Todos"
    assert screen =~ "0 todos, 0 done"
    assert screen =~ "nothing to do yet — press a to add one"
  end

  describe "the columns" do
    test "are the fields the schema puts in the list", %{ui: ui} do
      add(ui, "Write the docs")
      screen = text(ui)

      assert screen =~ "Title"
      assert screen =~ "Priority"
      assert screen =~ "Done"
      assert screen =~ "Created"
      assert screen =~ "Checked off"

      # A field marked "list": false is not one of them.
      refute screen |> row("Title") =~ "Description"
    end

    test "hold what the record holds", %{ui: ui} do
      add(ui, "Write the docs")
      line = text(ui) |> row("Write the docs")

      assert line =~ "▸ Write the docs"
      assert line =~ "2"
      assert line =~ "[ ]"
      assert line =~ ~r/\d{4}-\d\d-\d\d \d\d:\d\d/
    end
  end

  test "a adds one through the form, and it lands on disk", %{ui: ui, schema: schema} do
    assert press(ui, {:char, "a"}) =~ "New todo"
    assert Runtime.view_stack(ui) == [Form, Todo]
    press(ui, :esc)

    screen = add(ui, "Write the docs")

    assert Runtime.view_stack(ui) == [Todo]
    assert screen =~ "▸ Write the docs"
    assert screen =~ "1 todo, 0 done"

    assert %{title: "Write the docs", priority: 2, done: false} = one(schema)
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

  describe "checking one off" do
    test "space marks it done, and again marks it not done", %{ui: ui, schema: schema} do
      add(ui, "Write the docs")

      assert press(ui, {:char, " "}) |> row("Write the docs") =~ "[x]"
      assert text(ui) =~ "1 todo, 1 done"
      assert %{done: true} = one(schema)

      assert press(ui, {:char, " "}) |> row("Write the docs") =~ "[ ]"
      assert %{done: false} = one(schema)
    end

    test "writes the moment it was ticked, and clears it when it is unticked",
         %{ui: ui, schema: schema} do
      add(ui, "Write the docs")
      assert one(schema)[:done_at] == nil

      press(ui, {:char, " "})
      assert %{done: true, done_at: at} = one(schema)
      assert {:ok, _at, 0} = DateTime.from_iso8601(at)
      assert text(ui) |> row("Write the docs") =~ ~r/\d\d:\d\d.*\d\d:\d\d/

      press(ui, {:char, " "})
      assert %{done: false, done_at: nil} = one(schema)
    end

    test "editing something else leaves the date alone", %{ui: ui, schema: schema} do
      add(ui, "Write the docs")
      press(ui, {:char, " "})
      ticked = one(schema)[:done_at]

      press(ui, :enter)
      press(ui, [:end, {:char, "!"}, :enter])
      settle(ui)

      assert %{title: "Write the docs!", done: true, done_at: ^ticked} = one(schema)
    end
  end

  describe "sorting" do
    setup %{ui: ui} do
      add(ui, "Beta")
      press(ui, :enter)
      press(ui, [:tab, :tab, :end, :backspace, {:char, "9"}, :enter])
      settle(ui)

      add(ui, "alpha")

      :ok
    end

    test "starts on the column the schema names", %{ui: ui} do
      assert text(ui) =~ "Created ▲"
      assert text(ui) =~ "sorted by Created ▲"
      assert titles(ui) == ["Beta", "alpha"]
    end

    test "the arrows walk the sort along the columns", %{ui: ui} do
      assert press(ui, :left) =~ "Done ▲"
      assert press(ui, :left) =~ "Priority ▲"
      assert titles(ui) == ["alpha", "Beta"]

      assert press(ui, :left) =~ "Title ▲"
      assert titles(ui) == ["alpha", "Beta"]

      # And around the other way.
      assert press(ui, :right) =~ "Priority ▲"
      assert press(ui, :left) |> String.contains?("Title ▲")
    end

    test "s turns the column the other way up", %{ui: ui} do
      press(ui, [:left, :left, :left])
      assert titles(ui) == ["alpha", "Beta"]

      assert press(ui, {:char, "s"}) =~ "Title ▼"
      assert titles(ui) == ["Beta", "alpha"]
      assert text(ui) =~ "sorted by Title ▼"
    end

    test "the cursor stays on the todo it was on", %{ui: ui} do
      press(ui, :down)
      assert text(ui) =~ "▸ alpha"

      press(ui, [:left, :left, :left])
      assert text(ui) =~ "▸ alpha"
    end

    test "an empty cell goes last, whichever way up the column is", %{ui: ui} do
      # Only Beta has been checked off, so only Beta has a date to sort by.
      press(ui, {:char, " "})
      press(ui, :right)

      assert text(ui) =~ "Checked off ▲"
      assert titles(ui) == ["Beta", "alpha"]

      press(ui, {:char, "s"})
      assert titles(ui) == ["Beta", "alpha"]
    end
  end

  test "what does not fit in a column is shown beside the list", %{ui: ui} do
    add(ui, "Write the docs")
    press(ui, :enter)
    press(ui, [:tab])
    type(ui, "the ones in the readme")
    press(ui, :enter)
    screen = settle(ui)

    assert screen =~ "Description: the ones in the readme"
    refute screen |> row("Write the docs") =~ "readme"
  end

  test "the arrows move the cursor through the list", %{ui: ui} do
    add(ui, "First")
    add(ui, "Second")

    assert text(ui) =~ "▸ First"
    assert press(ui, :down) =~ "▸ Second"
    assert press(ui, :down) =~ "▸ First"
    assert press(ui, {:char, "j"}) =~ "▸ Second"
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
