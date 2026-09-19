defmodule ITui.SchemaTest do
  use ExUnit.Case, async: true
  doctest ITui.Schema
  doctest ITui.Schema.Field

  alias ITui.Schema
  alias ITui.Schema.Field

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
      assert %Field{type: :boolean, default: false} = done
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
      json = ~s({"name": "t", "fields": [{"name": "n", "type": "date"}]})
      assert {:error, message} = Schema.parse(json)
      assert message =~ ~s(unknown type "date")
      assert message =~ "known types: boolean, integer, string"
    end

    test "rejects a default the field could not hold" do
      json = ~s({"name": "t", "fields": [{"name": "n", "type": "integer", "default": "many"}]})
      assert {:error, message} = Schema.parse(json)
      assert message =~ ~s(the default of "n" must be a whole number)
    end
  end

  describe "cast/2" do
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

    test "casts every field, and fills in the defaults", %{schema: schema} do
      assert {:ok, values} = Schema.cast(schema, %{"title" => "  Write it  "})

      # A field nobody mentioned and nothing defaults is empty, not "".
      assert values == %{"title" => "Write it", "count" => 2, "done" => false, "note" => nil}
      assert {:ok, %{"note" => ""}} = Schema.cast(schema, %{"title" => "x", "note" => "  "})
    end

    test "reads yes and no as well as true and false", %{schema: schema} do
      assert {:ok, %{"done" => true}} = Schema.cast(schema, %{"title" => "x", "done" => "yes"})
      assert {:ok, %{"done" => false}} = Schema.cast(schema, %{"title" => "x", "done" => "no"})
      assert {:ok, %{"done" => true}} = Schema.cast(schema, %{"title" => "x", "done" => true})
    end

    test "reports every mistake at once, in the order of the fields", %{schema: schema} do
      assert {:error, errors} = Schema.cast(schema, %{"count" => "two", "done" => "maybe"})

      assert errors == [
               {"title", "is required"},
               {"count", "must be a whole number"},
               {"done", "must be yes or no"}
             ]
    end

    test "casting named fields leaves the others alone", %{schema: schema} do
      assert Schema.cast(schema, %{"done" => true, "title" => "x"}, ["done"]) ==
               {:ok, %{"done" => true}}
    end

    test "ignores keys the schema does not declare", %{schema: schema} do
      assert {:ok, values} = Schema.cast(schema, %{"title" => "x", "nonsense" => "y"})
      refute Map.has_key?(values, "nonsense")
    end
  end

  describe "load/1" do
    test "reads a schema by name from the data directory" do
      assert {:ok, schema} = Schema.load("todo")
      assert schema.source == "data/records/todos.json"
      assert Enum.map(schema.fields, & &1.name) == ["title", "priority", "done"]
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
