defmodule ITui.CLI.TodoTest do
  use ExUnit.Case, async: true

  alias ITui.{Repo, Schema}
  alias ITui.CLI.Todo

  @schema """
  {"name": "todo", "label": "Todo", "title": "Todos",
   "columns": ["id", "done", "priority", "due", "title"],
   "sort": "id",
   "fields": [
    {"name": "title", "label": "Title", "required": true, "placeholder": "what to do"},
    {"name": "description", "label": "Description", "lines": 3},
    {"name": "priority", "label": "Priority", "short": "P", "type": "integer", "default": 2},
    {"name": "due", "label": "Due", "type": "date"},
    {"name": "done", "label": "Done", "type": "boolean", "default": false},
    {"name": "id", "label": "#", "type": "integer", "form": false},
    {"name": "done_at", "label": "Checked", "type": "datetime", "form": false}
  ]}
  """

  setup do
    source = Path.join(System.tmp_dir!(), "i_tui_#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(source) end)

    {:ok, schema} = Schema.parse(@schema)

    %{schema: %{schema | source: source}}
  end

  defp stored(schema), do: schema |> Repo.all() |> elem(1)

  describe "add/2" do
    test "the words left over are what the todo is called", %{schema: schema} do
      assert Todo.add(schema, ["Buy", "milk"]) == {:say, "added #1 Buy milk"}

      assert [%{id: 1, title: "Buy milk", priority: 2, done: false}] = stored(schema)
    end

    test "every field the form asks for is an option", %{schema: schema} do
      argv = ["Write it", "--priority", "1", "--due", "2026-12-24", "--description", "at length"]

      assert {:say, "added #1 Write it"} = Todo.add(schema, argv)

      assert [%{priority: 1, due: "2026-12-24", description: "at length"}] = stored(schema)
    end

    test "a yes/no field is the option on its own", %{schema: schema} do
      assert {:say, _said} = Todo.add(schema, ["Already done", "--done"])

      assert [%{done: true}] = stored(schema)
    end

    test "a day may be said as how far off it is", %{schema: schema} do
      assert {:say, _said} = Todo.add(schema, ["Soon", "--due", "in 3 days"])

      [%{due: due}] = stored(schema)
      # The day it is where the person typing it is, as the form reckons it.
      assert due == ITui.Schema.Date.local_today() |> Date.add(3) |> Date.to_iso8601()
    end

    test "the title may be given as an option instead", %{schema: schema} do
      assert {:say, "added #1 Buy milk"} = Todo.add(schema, ["--title", "Buy milk"])
    end

    test "refuses to be told the title twice", %{schema: schema} do
      assert {:error, message} = Todo.add(schema, ["Buy milk", "--title", "Buy bread"])
      assert message == ~s(--title was given as well as "Buy milk")
    end

    test "says what the schema says about a value it will not take", %{schema: schema} do
      assert Todo.add(schema, ["Buy milk", "--priority", "soon"]) ==
               {:error, "Priority must be a whole number"}

      assert Todo.add(schema, ["Buy milk", "--due", "thursdayish"]) ==
               {:error, "Due must be a date, as 2026-09-25 or in 3 days"}
    end

    test "a todo with nothing to call it is refused", %{schema: schema} do
      assert Todo.add(schema, ["--priority", "1"]) == {:error, "Title is required"}
    end

    test "an option that is not a field says what the fields are", %{schema: schema} do
      assert {:error, message} = Todo.add(schema, ["Buy milk", "--colour", "red"])

      assert message =~ "there is no --colour on a todo"
      assert message =~ "--title, --description, --priority, --due, --done"
    end
  end

  describe "check/2" do
    setup %{schema: schema} do
      {:say, _said} = Todo.add(schema, ["Buy milk"])
      {:say, _said} = Todo.add(schema, ["Write the docs"])

      :ok
    end

    test "ticks the todo with that number, and says which it was", %{schema: schema} do
      assert Todo.check(schema, ["2"]) == {:say, "checked off #2 Write the docs"}

      assert [%{id: 1, done: false}, %{id: 2, done: true, done_at: at}] = stored(schema)
      assert at =~ ~r/^\d{4}-\d{2}-\d{2}T/
    end

    test "checks off several at once", %{schema: schema} do
      assert {:say, said} = Todo.check(schema, ["1", "2"])
      assert said == "checked off #1 Buy milk\nchecked off #2 Write the docs"
    end

    test "one that is already done is left as it was", %{schema: schema} do
      {:say, _said} = Todo.check(schema, ["1"])
      [%{done_at: at} | _rest] = stored(schema)

      assert Todo.check(schema, ["1"]) == {:say, "#1 Buy milk was already done"}
      assert [%{done_at: ^at} | _rest] = stored(schema)
    end

    test "needs a number", %{schema: schema} do
      assert {:error, message} = Todo.check(schema, [])
      assert message =~ "takes the number of a todo"

      assert Todo.check(schema, ["milk"]) == {:error, ~s("milk" is not the number of a todo)}
    end

    test "nothing is written when one of the numbers is not there", %{schema: schema} do
      assert Todo.check(schema, ["1", "99"]) == {:error, "no todo with id 99"}

      assert [%{done: false}, %{done: false}] = stored(schema)
    end
  end

  describe "list/2" do
    setup %{schema: schema} do
      {:say, _said} = Todo.add(schema, ["Buy milk", "--due", "yesterday", "--priority", "1"])
      {:say, _said} = Todo.add(schema, ["Write the docs"])
      {:say, _said} = Todo.check(schema, ["2"])

      :ok
    end

    defp lines({:say, text}), do: String.split(text, "\n")

    test "prints the columns the schema names, in the order it names them", %{schema: schema} do
      [heading, rule, first, second] = lines(Todo.list(schema, []))

      assert heading == "#  Done  P  Due         Title"
      assert rule == "─  ────  ─  ──────────  ──────────────"
      assert first =~ ~r/^1  \[ \]   1  \d{4}-\d{2}-\d{2}  Buy milk$/
      assert second == "2  [x]   2              Write the docs"
    end

    test "--hide leaves out the kinds it names", %{schema: schema} do
      assert [_heading, _rule, row] = lines(Todo.list(schema, ["--hide", "done"]))
      assert row =~ "Buy milk"
    end

    test "--only shows nothing else", %{schema: schema} do
      assert [_heading, _rule, first, second] =
               lines(Todo.list(schema, ["--only", "overdue,done"]))

      assert first =~ "Buy milk"
      assert second =~ "Write the docs"

      assert [_heading, _rule, row] = lines(Todo.list(schema, ["--only", "done"]))
      assert row =~ "Write the docs"
    end

    test "the option may be said again instead of listed", %{schema: schema} do
      assert Todo.list(schema, ["--only", "overdue", "--only", "done"]) ==
               Todo.list(schema, ["--only", "overdue,done"])
    end

    test "says so when there is nothing left to show", %{schema: schema} do
      assert Todo.list(schema, ["--hide", "done,overdue"]) == {:say, "no todos to show"}
    end

    test "a kind that is not one says what the kinds are", %{schema: schema} do
      assert {:error, message} = Todo.list(schema, ["--only", "urgent"])

      assert message ==
               ~s(there is no "urgent" kind of todo; ) <>
                 "there is: done, overdue, soon, week, month, later, none"
    end

    test "takes no words of its own", %{schema: schema} do
      assert {:error, message} = Todo.list(schema, ["done"])
      assert message =~ "takes no words"
    end
  end
end
