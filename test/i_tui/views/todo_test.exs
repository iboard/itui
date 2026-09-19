defmodule ITui.Views.TodoTest do
  use ITui.UICase, async: false

  alias ITui.{Repo, Schema}
  alias ITui.Views.{Form, Todo}

  @schema """
  {"name": "todo", "label": "Todo", "title": "Todos",
   "columns": ["id", "done", "priority", "inserted_at", "done_at", "title"],
   "sort": "inserted_at",
   "fields": [
    {"name": "title", "label": "Title", "required": true, "placeholder": "what to do"},
    {"name": "description", "label": "Description", "lines": 3},
    {"name": "priority", "label": "Priority", "short": "P", "type": "integer", "default": 2},
    {"name": "done", "label": "Done", "type": "boolean", "default": false},
    {"name": "id", "label": "#", "type": "integer", "form": false},
    {"name": "inserted_at", "label": "Created", "type": "datetime", "form": false},
    {"name": "done_at", "label": "Checked off", "type": "datetime", "form": false}
  ]}
  """

  setup do
    source = Path.join(System.tmp_dir!(), "i_tui_#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(source) end)

    {:ok, schema} = Schema.parse(@schema)
    schema = %{schema | source: source}

    %{schema: schema, source: source, ui: start_ui(Todo, schema: schema, size: {96, 16})}
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
    test "are the ones the schema names, in the order it names them", %{ui: ui} do
      add(ui, "Write the docs")
      headings = text(ui) |> row("Checked off")

      assert headings =~ ~r/#.*Done.*P.*Created.*Checked off.*Title/

      # A label too wide for a column is headed by its short one.
      refute headings =~ "Priority"

      # A field the columns leave out is not one of them.
      refute headings =~ "Description"
    end

    test "are ruled off from the list, and from each other", %{ui: ui} do
      add(ui, "Write the docs")
      screen = text(ui)

      assert screen |> row("Checked off") =~ "│"
      assert screen |> row("Write the docs") =~ "│"

      # The rule meets the box on both sides and the dividers where they cross.
      rule = screen |> String.split("\r\n") |> Enum.find("", &(&1 =~ "├"))
      assert String.starts_with?(rule, "├")
      assert String.ends_with?(rule, "┤")
      assert rule =~ "┼"
    end

    test "hold what the record holds", %{ui: ui} do
      add(ui, "Write the docs")
      line = text(ui) |> row("Write the docs")

      assert line =~ "▸"
      assert line =~ "1"
      assert line =~ "2"
      assert line =~ "[ ]"
      assert line =~ ~r/\d{4}-\d\d-\d\d/
    end

    test "the serial number is the one the repository gave it", %{ui: ui, schema: schema} do
      add(ui, "First")
      add(ui, "Second")

      press(ui, [{:char, "d"}, {:char, "y"}])

      assert %{id: 2, title: "Second"} = one(schema)
      assert text(ui) |> row("Second") =~ "2"

      # A serial number is not handed out twice, even when one is given up.
      add(ui, "Third")
      assert Repo.all(schema) |> elem(1) |> Enum.map(& &1[:id]) == [2, 3]
    end
  end

  test "a adds one through the form, and it lands on disk", %{ui: ui, schema: schema} do
    assert press(ui, {:char, "a"}) =~ "New todo"
    assert Runtime.view_stack(ui) == [Form, Todo]
    press(ui, :esc)

    screen = add(ui, "Write the docs")

    assert Runtime.view_stack(ui) == [Todo]
    assert screen |> row("Write the docs") =~ "▸"
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
      # Both dates are in the row now: the one it was made on, and this one.
      assert text(ui) |> row("Write the docs") =~ ~r/\d{4}-\d\d-\d\d.*\d{4}-\d\d-\d\d/

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
      assert press(ui, :left) =~ "P ▲"
      assert titles(ui) == ["alpha", "Beta"]

      assert press(ui, :left) =~ "Done ▲"

      assert press(ui, :left) =~ "# ▲"
      assert titles(ui) == ["Beta", "alpha"]

      # And around the other way.
      assert press(ui, :right) =~ "Done ▲"
      assert press(ui, [:right, :right, :right, :right]) =~ "Title ▲"
      assert titles(ui) == ["alpha", "Beta"]
    end

    test "r turns the column the other way up", %{ui: ui} do
      press(ui, [:right, :right])
      assert text(ui) =~ "Title ▲"
      assert titles(ui) == ["alpha", "Beta"]

      assert press(ui, {:char, "r"}) =~ "Title ▼"
      assert titles(ui) == ["Beta", "alpha"]
      assert text(ui) =~ "sorted by Title ▼"
    end

    test "the cursor stays on the todo it was on", %{ui: ui} do
      press(ui, :down)
      assert text(ui) |> row("alpha") =~ "▸"

      press(ui, [:left, :left, :left])
      assert text(ui) |> row("alpha") =~ "▸"
    end

    test "an empty cell goes last, whichever way up the column is", %{ui: ui} do
      # Only Beta has been checked off, so only Beta has a date to sort by.
      press(ui, {:char, " "})
      press(ui, :right)

      assert text(ui) =~ "Checked off ▲"
      assert titles(ui) == ["Beta", "alpha"]

      press(ui, {:char, "r"})
      assert titles(ui) == ["Beta", "alpha"]
    end
  end

  test "a row is kept for each thing shown beside the list, full or empty", %{ui: ui} do
    add(ui, "No description")

    # The list does not shuffle about as the cursor moves over an empty one.
    assert text(ui) =~ "a add · enter edit"
    refute text(ui) =~ "Description:"
  end

  test "what does not fit in a column is shown beside the list", %{ui: ui} do
    add(ui, "Write the docs")
    press(ui, :enter)
    press(ui, [:tab])
    type(ui, "the ones in the readme,")
    press(ui, :enter)
    type(ui, "and the moduledocs")
    press(ui, {[:ctrl], "d"})
    screen = settle(ui)

    # A description of several lines has to say it in one, down there.
    assert screen =~ "Description: the ones in the readme, and the moduledocs"
    refute screen |> row("Write the docs") =~ "readme"
  end

  test "the arrows move the cursor through the list", %{ui: ui} do
    add(ui, "First")
    add(ui, "Second")

    assert text(ui) |> row("First") =~ "▸"
    assert press(ui, :down) |> row("Second") =~ "▸"
    assert press(ui, :down) |> row("First") =~ "▸"
    assert press(ui, {:char, "j"}) |> row("Second") =~ "▸"
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

  test "R re-reads the file", %{ui: ui, schema: schema} do
    {:ok, _record} = Repo.insert(schema, %{"title" => "Added behind its back"})

    refute text(ui) =~ "Added behind its back"
    assert press(ui, {:char, "R"}) =~ "Added behind its back"
  end
end

defmodule ITui.Views.TodoStretchTest do
  use ITui.UICase, async: false

  alias ITui.{Repo, Schema}
  alias ITui.Views.Todo

  @schema """
  {"name": "note", "label": "Note", "columns": ["id", "title", "body"], "stretch": "body",
   "detail": ["body"],
   "fields": [
    {"name": "title", "label": "Title", "required": true},
    {"name": "body", "label": "Body", "lines": 3},
    {"name": "id", "label": "#", "type": "integer", "form": false}
  ]}
  """

  setup do
    source = Path.join(System.tmp_dir!(), "i_tui_#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(source) end)

    {:ok, schema} = Schema.parse(@schema)
    schema = %{schema | source: source}

    {:ok, _record} =
      Repo.insert(schema, %{
        "title" => "Short",
        "body" => "a body long enough to be cut down to whatever room is left over"
      })

    %{schema: schema}
  end

  defp body_column(ui) do
    ui
    |> text()
    |> String.split("\r\n")
    |> Enum.find("", &(&1 =~ "a body"))
    |> String.split("│")
    # The last piece is what follows the box's own right border.
    |> Enum.drop(-1)
    |> List.last()
    |> String.trim()
  end

  test "the column the schema names takes the room the others leave", %{schema: schema} do
    ui = start_ui(Todo, schema: schema, size: {80, 10})

    assert String.length(body_column(ui)) > 40
    assert body_column(ui) =~ "a body long enough"
  end

  test "a column can be repeated in full beside the list", %{schema: schema} do
    ui = start_ui(Todo, schema: schema, size: {46, 10})
    lines = ui |> text() |> String.split("\r\n")

    detail = Enum.find(lines, "", &(&1 =~ "Body:"))

    assert detail =~ "Body: a body long enough"
    assert String.length(body_column(ui)) < String.length(detail)
  end

  test "and gives it back when there is less of it", %{schema: schema} do
    ui = start_ui(Todo, schema: schema, size: {46, 10})
    shown = body_column(ui)

    assert String.length(shown) < 30
    assert String.starts_with?("a body long enough to be cut down", shown)

    # The other columns are untouched: the stretching one took the squeeze.
    assert text(ui) =~ "Short"
  end
end

defmodule ITui.Views.TodoColourTest do
  use ITui.UICase, async: false

  alias ITui.{Repo, Schema}
  alias ITui.Views.Todo

  # A Monday, so that "later this week" is a day that exists.
  @today ~D[2026-09-14]

  @schema """
  {"name": "todo", "label": "Todo", "columns": ["id", "done", "due", "title"], "sort": "id",
   "fields": [
    {"name": "title", "label": "Title", "required": true},
    {"name": "due", "label": "Due", "type": "date"},
    {"name": "done", "label": "Done", "type": "boolean", "default": false},
    {"name": "id", "label": "#", "type": "integer", "form": false}
  ]}
  """

  setup do
    source = Path.join(System.tmp_dir!(), "i_tui_#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(source) end)

    {:ok, schema} = Schema.parse(@schema)

    %{schema: %{schema | source: source}}
  end

  defp with_todos(schema, todos) do
    for attrs <- todos, do: {:ok, _record} = Repo.insert(schema, attrs)

    start_ui(Todo, schema: schema, today: @today, size: {70, 14})
  end

  defp tones(ui) do
    state = Runtime.view_state(ui, Todo)

    Enum.map(state.todos, &{&1[:title], Todo.tone(state, &1)})
  end

  defp style(ui, row) do
    {_grapheme, style} = ui |> Runtime.screen() |> Atui.Screen.cell(2, 4 + row)

    style
  end

  test "today is at the top, and is the day the colours are reckoned from", %{schema: schema} do
    ui = with_todos(schema, [%{"title" => "Due on the Thursday", "due" => "2026-09-17"}])

    # A Monday, so the Thursday is still inside this week.
    assert text(ui) =~ "Mon 2026-09-14 · 1 todo, 0 done"
    assert tones(ui) == [{"Due on the Thursday", :week}]
  end

  test "is how near the due date is, and green once it is done", %{schema: schema} do
    ui =
      with_todos(schema, [
        %{"title" => "Overdue", "due" => "2026-09-11"},
        %{"title" => "Today", "due" => "2026-09-14"},
        %{"title" => "In two days", "due" => "2026-09-16"},
        %{"title" => "Later this week", "due" => "2026-09-17"},
        %{"title" => "Sunday, the last of it", "due" => "2026-09-20"},
        %{"title" => "Next week", "due" => "2026-09-21"},
        %{"title" => "The last of the month", "due" => "2026-09-30"},
        %{"title" => "The first of the next", "due" => "2026-10-01"},
        %{"title" => "Whenever"},
        %{"title" => "Done, and was overdue", "due" => "2026-09-01", "done" => true}
      ])

    assert tones(ui) == [
             {"Overdue", :overdue},
             {"Today", :soon},
             {"In two days", :soon},
             {"Later this week", :week},
             {"Sunday, the last of it", :week},
             {"Next week", :month},
             {"The last of the month", :month},
             {"The first of the next", :later},
             {"Whenever", :none},
             {"Done, and was overdue", :done}
           ]
  end

  test "is drawn in the colour it says, cursor or no cursor", %{schema: schema} do
    ui =
      with_todos(schema, [
        %{"title" => "Overdue", "due" => "2026-09-11"},
        %{"title" => "In two days", "due" => "2026-09-16"},
        %{"title" => "Later this week", "due" => "2026-09-17"},
        %{"title" => "Next week", "due" => "2026-09-21"},
        %{"title" => "Next month", "due" => "2026-10-05"},
        %{"title" => "Done", "done" => true}
      ])

    # The row the cursor is on keeps its colour and takes a background.
    assert %{fg: :bright_red, bg: :bright_black, bold: true} = style(ui, 0)

    assert %{fg: :bright_yellow, bg: nil} = style(ui, 1)
    assert %{fg: 208, bg: nil} = style(ui, 2)
    assert %{fg: :white, bg: nil} = style(ui, 3)
    assert %{fg: 117, bg: nil} = style(ui, 4)
    assert %{fg: :green, bg: nil} = style(ui, 5)

    # Moving the cursor moves the background, not the colour.
    press(ui, :down)
    assert %{fg: :bright_red, bg: nil} = style(ui, 0)
    assert %{fg: :bright_yellow, bg: :bright_black} = style(ui, 1)
  end

  test "a due date is asked for in the form, and is not required", %{schema: schema} do
    ui = with_todos(schema, [])

    press(ui, {:char, "a"})
    type(ui, "No date for this one")
    press(ui, :enter)

    assert settle(ui) =~ "No date for this one"
    assert Repo.all(schema) |> elem(1) |> hd() |> Map.fetch!(:due) == nil
  end

  test "a due date that is not a date is refused, and says how one looks", %{schema: schema} do
    ui = with_todos(schema, [])

    press(ui, {:char, "a"})
    type(ui, "Some day")
    press(ui, :tab)
    type(ui, "next tuesday")
    screen = press(ui, :enter)

    assert screen =~ "Due must be a date, as 2026-09-25"
    assert Repo.all(schema) == {:ok, []}
  end
end

defmodule ITui.Views.TodoShowingTest do
  use ITui.UICase, async: false

  alias ITui.{Repo, Schema}
  alias ITui.Views.{Filter, Todo}

  @today ~D[2026-09-14]

  @schema """
  {"name": "todo", "label": "Todo", "columns": ["id", "done", "due", "title"], "sort": "id",
   "fields": [
    {"name": "title", "label": "Title", "required": true},
    {"name": "due", "label": "Due", "type": "date"},
    {"name": "done", "label": "Done", "type": "boolean", "default": false},
    {"name": "id", "label": "#", "type": "integer", "form": false}
  ]}
  """

  setup do
    source = Path.join(System.tmp_dir!(), "i_tui_#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(source) end)

    {:ok, schema} = Schema.parse(@schema)
    schema = %{schema | source: source}

    for attrs <- [
          %{"title" => "Overdue", "due" => "2026-09-09"},
          %{"title" => "Tomorrow", "due" => "2026-09-15"},
          %{"title" => "Thursday", "due" => "2026-09-17"},
          %{"title" => "Next month", "due" => "2026-10-24"},
          %{"title" => "Whenever"},
          %{"title" => "Finished", "done" => true}
        ] do
      {:ok, _record} = Repo.insert(schema, attrs)
    end

    %{schema: schema, ui: start_ui(Todo, schema: schema, today: @today, size: {80, 16})}
  end

  defp titles(ui) do
    ui |> Runtime.view_state(Todo) |> Map.fetch!(:todos) |> Enum.map(& &1[:title])
  end

  describe "t, for how the dates are written" do
    test "turns them into how they stand from today, and back", %{ui: ui} do
      assert text(ui) =~ "2026-09-15"

      screen = press(ui, {:char, "t"})
      assert screen =~ "-5 days"
      assert screen =~ "+1 day"
      assert screen =~ "+3 days"
      assert screen =~ "+6 weeks"
      refute screen =~ "2026-09-15"

      assert press(ui, {:char, "t"}) =~ "2026-09-15"
    end

    test "leaves a todo with no date with nothing to say", %{ui: ui} do
      line =
        ui
        |> press({:char, "t"})
        |> String.split("\r\n")
        |> Enum.find("", &(&1 =~ "Whenever"))

      refute line =~ "day"
      refute line =~ "today"
    end
  end

  describe "f, for which kinds are shown" do
    test "opens on the bands, with how many there are of each", %{ui: ui} do
      screen = press(ui, {:char, "f"})

      assert Runtime.view_stack(ui) == [Filter, Todo]
      assert screen =~ "Show"
      assert screen =~ "[x] Overdue"
      assert screen =~ "[x] No due date"
    end

    test "the list changes as the boxes are ticked, not when the popup closes", %{ui: ui} do
      press(ui, {:char, "f"})

      assert titles(ui) == [
               "Overdue",
               "Tomorrow",
               "Thursday",
               "Next month",
               "Whenever",
               "Finished"
             ]

      press(ui, {:char, " "})
      screen = settle(ui)

      # The popup is still open, and the list behind it has already changed.
      assert Runtime.view_stack(ui) == [Filter, Todo]
      assert screen =~ "5 of 6 todos"
      assert titles(ui) == ["Overdue", "Tomorrow", "Thursday", "Next month", "Whenever"]

      press(ui, [:down, {:char, " "}])
      assert settle(ui) =~ "4 of 6 todos"
      assert titles(ui) == ["Tomorrow", "Thursday", "Next month", "Whenever"]

      # And a shows them all again, there and then.
      press(ui, {:char, "a"})
      assert settle(ui) =~ "6 todos, 1 done"
      assert length(titles(ui)) == 6
    end

    test "hiding a kind takes it off the list, and says so in the summary", %{ui: ui} do
      assert text(ui) =~ "6 todos, 1 done"

      press(ui, {:char, "f"})
      # Done is the first band.
      press(ui, {:char, " "})
      press(ui, :esc)
      screen = settle(ui)

      assert Runtime.view_stack(ui) == [Todo]
      assert screen =~ "5 of 6 todos"
      refute screen =~ "Finished"
      assert titles(ui) == ["Overdue", "Tomorrow", "Thursday", "Next month", "Whenever"]
    end

    test "hiding several of them, and showing them all again", %{ui: ui} do
      press(ui, {:char, "f"})
      press(ui, [{:char, " "}, :down, {:char, " "}, :down, :down, :down, :down, {:char, " "}])
      press(ui, :esc)
      settle(ui)

      assert titles(ui) == ["Tomorrow", "Thursday", "Whenever"]
      assert text(ui) =~ "3 of 6 todos"

      press(ui, {:char, "f"})
      press(ui, {:char, "a"})
      press(ui, :esc)
      screen = settle(ui)

      assert length(titles(ui)) == 6
      assert screen =~ "6 todos, 1 done"
    end

    test "what is hidden stays hidden when the file is read again", %{ui: ui, schema: schema} do
      press(ui, {:char, "f"})
      press(ui, {:char, " "})
      press(ui, :esc)
      settle(ui)

      {:ok, _record} = Repo.insert(schema, %{"title" => "Added later"})

      screen = press(ui, {:char, "R"})

      assert screen =~ "Added later"
      refute screen =~ "Finished"
      assert screen =~ "6 of 7 todos"
    end

    test "the cursor stays on the todo it was on", %{ui: ui} do
      press(ui, [:down, :down])
      assert text(ui) =~ "▸"
      assert Enum.at(titles(ui), Runtime.view_state(ui, Todo).cursor) == "Thursday"

      press(ui, {:char, "f"})
      press(ui, {:char, " "})
      press(ui, :esc)
      settle(ui)

      assert Enum.at(titles(ui), Runtime.view_state(ui, Todo).cursor) == "Thursday"
    end
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
