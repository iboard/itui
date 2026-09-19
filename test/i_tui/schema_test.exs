defmodule ITui.SchemaTest do
  use ExUnit.Case, async: true
  doctest ITui.Schema
  doctest ITui.Schema.Field

  alias ITui.Schema
  alias ITui.Schema.{Boolean, Field, Timestamp}

  defp messages({:error, changeset}, schema) do
    schema |> Schema.errors(changeset) |> Enum.map(fn {f, m} -> {f.label, m} end)
  end

  describe "parse/1" do
    test "reads the fields, their types and their defaults" do
      json = """
      {
        "name": "todo",
        "label": "Todo",
        "title": "Todos",
        "source": "tmp/todos.json",
        "fields": [
          {"name": "title", "label": "Title", "required": true, "placeholder": "what to do"},
          {"name": "priority", "type": "integer", "default": 2},
          {"name": "done", "type": "boolean", "default": false}
        ]
      }
      """

      assert {:ok, schema} = Schema.parse(json)
      assert schema.name == "todo"
      assert schema.label == "Todo"
      assert schema.title == "Todos"
      assert schema.source == "tmp/todos.json"

      assert [title, priority, done] = schema.fields
      assert %Field{type: :string, required: true, placeholder: "what to do"} = title
      assert %Field{type: :integer, default: 2, required: false} = priority
      assert %Field{type: Boolean, default: false, key: :done} = done
    end

    test "a label is made from the name when there is none" do
      assert {:ok, schema} = Schema.parse(~s({"name": "note", "fields": [{"name": "due_at"}]}))
      assert schema.label == "Note"
      assert schema.title == "Note"
      assert [%Field{label: "Due at", type: :string}] = schema.fields
    end

    test "rejects a schema without fields, a name, or valid JSON" do
      assert {:error, ~s(a schema needs a "fields" list)} = Schema.parse(~s({"name": "x"}))
      assert {:error, message} = Schema.parse(~s({"fields": []}))
      assert message =~ "a schema needs a name"
      assert {:error, message} = Schema.parse("nope")
      assert message =~ "invalid JSON"
    end

    test "names the field that is wrong, and the schema it sits in" do
      assert {:error, message} = Schema.parse(~s({"name": "t", "fields": [{"label": "x"}]}))
      assert message =~ ~s(in "t": a field needs a name)
    end

    test "rejects an unknown type" do
      json = ~s({"name": "t", "fields": [{"name": "n", "type": "colour"}]})
      assert {:error, message} = Schema.parse(json)
      assert message =~ ~s(unknown type "colour")
      assert message =~ "known types: boolean, date, datetime, integer, string"
    end

    test "rejects a default the field could not hold" do
      json = ~s({"name": "t", "fields": [{"name": "n", "type": "integer", "default": "many"}]})
      assert {:error, message} = Schema.parse(json)
      assert message =~ ~s(the default of "n" must be a whole number)
    end
  end

  describe "cast/3" do
    setup do
      json = """
      {"name": "t", "fields": [
        {"name": "title", "required": true},
        {"name": "count", "type": "integer", "default": 2},
        {"name": "done", "type": "boolean"},
        {"name": "note"}
      ]}
      """

      {:ok, schema} = Schema.parse(json)

      %{schema: schema}
    end

    test "casts every field into a record, and fills in the defaults", %{schema: schema} do
      assert {:ok, values} = Schema.cast(schema, %{"title" => "  Write it  "})

      # A field nobody mentioned and nothing defaults is empty, not "".
      assert values == %{title: "Write it", count: 2, done: false, note: nil}
      assert {:ok, %{note: ""}} = Schema.cast(schema, %{"title" => "x", "note" => "  "})
    end

    test "reads yes and no as well as true and false", %{schema: schema} do
      assert {:ok, %{done: true}} = Schema.cast(schema, %{"title" => "x", "done" => "yes"})
      assert {:ok, %{done: false}} = Schema.cast(schema, %{"title" => "x", "done" => "no"})
      assert {:ok, %{done: true}} = Schema.cast(schema, %{"title" => "x", "done" => true})
    end

    test "reports every mistake at once, in the order of the fields", %{schema: schema} do
      result = Schema.cast(schema, %{"count" => "two", "done" => "maybe"})

      assert {:error, %Ecto.Changeset{valid?: false}} = result

      assert messages(result, schema) == [
               {"Title", "is required"},
               {"Count", "must be a whole number"},
               {"Done", "must be yes or no"}
             ]
    end

    test "only the named fields may be set", %{schema: schema} do
      assert Schema.cast(schema, %{"done" => true, "title" => "x"}, ["done"]) ==
               {:ok, %{title: nil, count: 2, done: true, note: nil}}
    end

    test "ignores keys the schema does not declare", %{schema: schema} do
      assert {:ok, values} = Schema.cast(schema, %{"title" => "x", "nonsense" => "y"})
      refute Map.has_key?(values, :nonsense)
    end
  end

  describe "change/4" do
    setup do
      json = """
      {"name": "t", "fields": [
        {"name": "title", "required": true},
        {"name": "count", "type": "integer", "default": 2},
        {"name": "done", "type": "boolean"}
      ]}
      """

      {:ok, schema} = Schema.parse(json)

      %{schema: schema, record: %{id: 7, title: "Write it", count: 1, done: false}}
    end

    test "applies the changes onto the record it was given", %{schema: schema, record: record} do
      assert Schema.change(schema, record, %{"done" => "yes"}, ["done"]) ==
               {:ok, %{id: 7, title: "Write it", count: 1, done: true}}
    end

    test "a field nobody named keeps what it had", %{schema: schema, record: record} do
      assert {:ok, changed} = Schema.change(schema, record, %{"count" => "9"}, ["count"])

      assert changed.title == "Write it"
      assert changed.count == 9
    end

    test "a change that does not cast is refused", %{schema: schema, record: record} do
      result = Schema.change(schema, record, %{"title" => "  "})

      assert messages(result, schema) == [{"Title", "is required"}]
    end

    test "clearing an optional field clears it", %{schema: schema, record: record} do
      assert {:ok, %{count: nil}} = Schema.change(schema, record, %{"count" => ""}, ["count"])
    end
  end

  describe "types/1 and defaults/1" do
    test "give Ecto what a changeset needs" do
      {:ok, schema} = Schema.load("todo")

      assert Schema.types(schema) == %{
               title: :string,
               description: :string,
               url: :string,
               priority: :integer,
               due: ITui.Schema.Date,
               done: Boolean,
               id: :integer,
               inserted_at: Timestamp,
               done_at: Timestamp
             }

      assert Schema.defaults(schema) == %{
               title: nil,
               description: nil,
               url: nil,
               priority: 2,
               due: nil,
               done: false,
               id: nil,
               inserted_at: nil,
               done_at: nil
             }
    end
  end

  describe "where a field belongs" do
    test "a field says whether it is asked for, and the schema which are columns" do
      json = """
      {"name": "t", "columns": ["c", "a"], "fields": [
        {"name": "a"},
        {"name": "b"},
        {"name": "c", "type": "datetime", "form": false}
      ]}
      """

      {:ok, schema} = Schema.parse(json)

      assert Enum.map(Schema.form_fields(schema), & &1.name) == ["a", "b"]
      assert Enum.map(Schema.list_fields(schema), & &1.name) == ["c", "a"]
      assert Enum.map(Schema.detail_fields(schema), & &1.name) == ["b"]
    end

    test "a schema can name what is shown beside the list, column or not" do
      json = """
      {"name": "t", "columns": ["a", "b"], "detail": ["b", "c"], "fields": [
        {"name": "a"}, {"name": "b"}, {"name": "c"}
      ]}
      """

      {:ok, schema} = Schema.parse(json)

      assert Enum.map(Schema.list_fields(schema), & &1.name) == ["a", "b"]
      assert Enum.map(Schema.detail_fields(schema), & &1.name) == ["b", "c"]
    end

    test "rejects a detail that is not made of fields" do
      json = ~s({"name": "t", "detail": ["z"], "fields": [{"name": "a"}]})
      assert {:error, message} = Schema.parse(json)
      assert message =~ ~s(the detail of "t" name something that is not a field: "z")

      json = ~s({"name": "t", "detail": "a", "fields": [{"name": "a"}]})
      assert {:error, message} = Schema.parse(json)
      assert message =~ ~s(the detail of "t" must be a list of field names)
    end

    test "every field is a column when the schema does not say otherwise" do
      {:ok, schema} = Schema.parse(~s({"name": "t", "fields": [{"name": "a"}, {"name": "b"}]}))

      assert Enum.map(Schema.list_fields(schema), & &1.name) == ["a", "b"]
      assert Schema.detail_fields(schema) == []
    end

    test "rejects lines that are not a count" do
      json = ~s({"name": "t", "fields": [{"name": "a", "lines": 0}]})
      assert {:error, message} = Schema.parse(json)
      assert message =~ ~s(the lines of "a" must be a whole number above zero)

      json = ~s({"name": "t", "fields": [{"name": "a", "lines": "many"}]})
      assert {:error, message} = Schema.parse(json)
      assert message =~ "must be a whole number above zero"
    end

    test "rejects columns that are not fields" do
      json = ~s({"name": "t", "columns": ["a", "z"], "fields": [{"name": "a"}]})
      assert {:error, message} = Schema.parse(json)
      assert message =~ ~s(the columns of "t" name something that is not a field: "z")

      json = ~s({"name": "t", "columns": "a", "fields": [{"name": "a"}]})
      assert {:error, message} = Schema.parse(json)
      assert message =~ "must be a list of field names"
    end

    test "a schema names the column its list starts sorted by, and the one that stretches" do
      json =
        ~s({"name": "t", "sort": "b", "stretch": "a", "fields": [{"name": "a"}, {"name": "b"}]})

      assert {:ok, %Schema{sort: :b, stretch: :a}} = Schema.parse(json)

      json = ~s({"name": "t", "sort": "z", "fields": [{"name": "a"}]})
      assert {:error, message} = Schema.parse(json)
      assert message =~ ~s(the sort of "t" is not one of its fields: "z")

      json = ~s({"name": "t", "stretch": "z", "fields": [{"name": "a"}]})
      assert {:error, message} = Schema.parse(json)
      assert message =~ ~s(the stretch of "t" is not one of its fields: "z")

      json = ~s({"name": "t", "stretch": 1, "fields": [{"name": "a"}]})
      assert {:error, message} = Schema.parse(json)
      assert message =~ "must be a field name"
    end
  end

  describe "the timestamp type" do
    test "casts what a record and a form can hold" do
      assert Timestamp.cast("2026-09-19T19:26:18Z") == {:ok, "2026-09-19T19:26:18Z"}
      assert Timestamp.cast(~U[2026-09-19 19:26:18.123Z]) == {:ok, "2026-09-19T19:26:18Z"}
      assert Timestamp.cast(nil) == {:ok, nil}
      assert Timestamp.cast("") == {:ok, nil}
      assert Timestamp.cast("last tuesday") == :error
    end

    test "is shown as the day it fell on, and sorts as it is stored" do
      assert Timestamp.format("2026-09-19T19:26:18Z") =~ ~r/^2026-09-\d\d$/
      assert Timestamp.width() == 10
      assert Timestamp.format(nil) == ""
      assert Timestamp.format("not a date") == "not a date"

      assert Enum.sort(["2026-01-02T00:00:00Z", "2025-12-31T23:59:59Z"]) ==
               ["2025-12-31T23:59:59Z", "2026-01-02T00:00:00Z"]
    end

    test "a datetime field reports what it will not take" do
      json = ~s({"name": "t", "fields": [{"name": "at", "type": "datetime"}]})
      {:ok, schema} = Schema.parse(json)

      result = Schema.cast(schema, %{"at" => "tomorrow"})

      assert messages(result, schema) == [{"At", "must be a date and time"}]
    end
  end

  describe "the date type" do
    test "takes a day, and a timestamp as the day it fell on" do
      assert ITui.Schema.Date.cast("2026-09-25") == {:ok, "2026-09-25"}
      assert ITui.Schema.Date.cast("  2026-09-25 ") == {:ok, "2026-09-25"}
      assert ITui.Schema.Date.cast(~D[2026-09-25]) == {:ok, "2026-09-25"}
      assert ITui.Schema.Date.cast("2026-09-25T19:26:18Z") == {:ok, "2026-09-25"}
      assert ITui.Schema.Date.cast(nil) == {:ok, nil}
      assert ITui.Schema.Date.cast("") == {:ok, nil}
    end

    test "refuses what is not one, and says how one is written" do
      assert ITui.Schema.Date.cast("25.09.2026") == :error
      assert ITui.Schema.Date.cast("2026-13-01") == :error
      assert ITui.Schema.Date.cast("3 fortnights") == :error
      assert ITui.Schema.Date.cast("3") == :error
      assert ITui.Schema.Date.cast("soon") == :error

      json = ~s({"name": "t", "fields": [{"name": "due", "type": "date"}]})
      {:ok, schema} = Schema.parse(json)

      assert messages(Schema.cast(schema, %{"due" => "whenever"}), schema) ==
               [{"Due", "must be a date, as 2026-09-25 or in 3 days"}]
    end

    test "takes a day said as how far off it is, and works it out from today" do
      today = ITui.Schema.Date.local_today()
      on = fn days -> {:ok, today |> Date.add(days) |> Date.to_iso8601()} end

      assert ITui.Schema.Date.cast("in 3 days") == on.(3)
      assert ITui.Schema.Date.cast("3 days") == on.(3)
      assert ITui.Schema.Date.cast("3days") == on.(3)
      assert ITui.Schema.Date.cast("3d") == on.(3)
      assert ITui.Schema.Date.cast("+3d") == on.(3)
      assert ITui.Schema.Date.cast("  3 d  ") == on.(3)
      assert ITui.Schema.Date.cast("IN 3 DAYS") == on.(3)

      assert ITui.Schema.Date.cast("3weeks") == on.(21)
      assert ITui.Schema.Date.cast("-2w") == on.(-14)

      assert ITui.Schema.Date.cast("today") == on.(0)
      assert ITui.Schema.Date.cast("tomorrow") == on.(1)
      assert ITui.Schema.Date.cast("yesterday") == on.(-1)

      # Months and years land on the same day of the month, not on a count of days.
      assert ITui.Schema.Date.cast("1 month") ==
               {:ok, today |> Date.shift(month: 1) |> Date.to_iso8601()}

      assert ITui.Schema.Date.cast("2 years") ==
               {:ok, today |> Date.shift(year: 2) |> Date.to_iso8601()}
    end

    test "and says it the other way round again" do
      assert "in 2 weeks"
             |> ITui.Schema.Date.cast()
             |> elem(1)
             |> ITui.Schema.Date.parse()
             |> ITui.Schema.Date.relative(ITui.Schema.Date.local_today()) == "+2 weeks"
    end

    test "is the same thing on the way in and on the way out" do
      json = ~s({"name": "t", "fields": [{"name": "due", "type": "date"}]})
      {:ok, schema} = Schema.parse(json)
      field = Schema.field(schema, :due)

      assert {:ok, %{due: "2026-09-25"}} = Schema.cast(schema, %{"due" => "2026-09-25"})
      assert Field.format(field, "2026-09-25") == "2026-09-25"
      assert Field.format(field, nil) == ""
      assert ITui.Schema.Date.parse("2026-09-25") == ~D[2026-09-25]
      assert ITui.Schema.Date.parse("whenever") == nil
    end
  end

  describe "a day as it stands from another one" do
    test "says it in the coarsest unit that still means something" do
      today = ~D[2026-09-14]
      on = fn days -> ITui.Schema.Date.relative(Date.add(today, days), today) end

      assert on.(0) == "today"
      assert on.(1) == "+1 day"
      assert on.(-1) == "-1 day"
      assert on.(13) == "+13 days"
      assert on.(14) == "+2 weeks"
      assert on.(-14) == "-2 weeks"
      assert on.(27) == "+4 weeks"
      assert on.(28) == "+1 month"
      assert on.(90) == "+3 months"
      assert on.(364) == "+12 months"
      assert on.(365) == "+1 year"
      assert on.(-730) == "-2 years"
      assert ITui.Schema.Date.relative(nil, today) == ""
    end

    test "a field says it for a date and a timestamp alike, and not for the rest" do
      json = """
      {"name": "t", "fields": [
        {"name": "due", "type": "date"},
        {"name": "at", "type": "datetime"},
        {"name": "title"}
      ]}
      """

      {:ok, schema} = Schema.parse(json)
      today = ~D[2026-09-14]

      assert Field.relative(Schema.field(schema, :due), "2026-09-17", today) == "+3 days"
      assert Field.relative(Schema.field(schema, :at), "2026-09-17T09:00:00Z", today) == "+3 days"
      assert Field.relative(Schema.field(schema, :due), nil, today) == ""
      assert Field.relative(Schema.field(schema, :title), "Write it", today) == "Write it"
    end
  end

  describe "the yes/no type" do
    test "takes the words a person types" do
      for yes <- ~w(true yes Y 1 on), do: assert(Boolean.cast(yes) == {:ok, true})
      for no <- ~w(false no N 0 OFF), do: assert(Boolean.cast(no) == {:ok, false})

      assert Boolean.cast(true) == {:ok, true}
      assert Boolean.cast("maybe") == :error
      assert Boolean.cast(3) == :error
    end

    test "stores and loads a plain boolean" do
      assert Boolean.dump(true) == {:ok, true}
      assert Boolean.load(false) == {:ok, false}
      assert Boolean.type() == :boolean
    end
  end

  describe "load/1" do
    test "reads a schema by name from the data directory" do
      assert {:ok, schema} = Schema.load("todo")
      assert schema.source == "records/todos.json"

      assert Enum.map(schema.fields, & &1.name) ==
               ~w(title description url priority due done id inserted_at done_at)

      assert schema.sort == :id

      # The table reads in a different order from the form that fills it.
      assert Enum.map(Schema.list_fields(schema), & &1.name) ==
               ~w(id done priority inserted_at due done_at title description)

      assert schema.stretch == :description

      # A label too wide for a column has a short one; a long field has lines.
      assert Schema.field(schema, :priority) |> Field.short() == "P"
      assert Schema.field(schema, :title) |> Field.short() == "Title"
      assert Schema.field(schema, :description).lines == 4
      assert Field.multiline?(Schema.field(schema, :description))
      refute Field.multiline?(Schema.field(schema, :title))

      # Description is a column and is repeated in full beside the list.
      assert Enum.map(Schema.detail_fields(schema), & &1.name) == ["description", "url"]

      # The due date is asked for; the ones the application writes are not.
      assert Enum.map(Schema.form_fields(schema), & &1.name) ==
               ~w(title description url priority due done)

      refute Schema.field(schema, :due).required
    end

    test "reads a schema from a path" do
      assert {:ok, %Schema{name: "word"}} = Schema.load("test/fixtures/word.json")
    end

    test "reports a schema that is not there" do
      assert {:error, message} = Schema.load("nonexistent")
      assert message =~ "data/schemas/nonexistent.json: no such file or directory"
    end
  end
end
