defmodule ITui.Repo.JsonTest do
  use ExUnit.Case, async: true

  alias ITui.Repo.Json
  alias ITui.Schema

  setup do
    source = Path.join(System.tmp_dir!(), "i_tui_#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(source) end)

    json = """
    {"name": "todo", "fields": [
      {"name": "title", "required": true},
      {"name": "priority", "type": "integer", "default": 2},
      {"name": "done", "type": "boolean", "default": false}
    ]}
    """

    {:ok, schema} = Schema.parse(json)

    %{schema: %{schema | source: source}, source: source}
  end

  test "a collection that has never been written reads as empty", %{schema: schema} do
    assert Json.all(schema) == {:ok, []}
  end

  test "inserting gives the record an id and timestamps", %{schema: schema} do
    assert {:ok, record} = Json.insert(schema, %{"title" => "Write it"})

    assert record[:id] == 1
    assert record[:title] == "Write it"
    assert record[:priority] == 2
    assert record[:done] == false
    assert {:ok, _at, 0} = DateTime.from_iso8601(record[:inserted_at])
    assert record[:updated_at] == record[:inserted_at]

    assert {:ok, second} = Json.insert(schema, %{"title" => "And again"})
    assert second[:id] == 2
  end

  test "the file is JSON anyone can read", %{schema: schema, source: source} do
    {:ok, _record} = Json.insert(schema, %{"title" => "Write it"})

    assert {:ok, [written]} = source |> File.read!() |> Jason.decode()
    assert written["title"] == "Write it"
    assert written["done"] == false
    assert String.ends_with?(File.read!(source), "\n")
  end

  test "a key nobody declared survives being written back", %{schema: schema, source: source} do
    File.write!(source, ~s([{"id": 1, "title": "Kept", "colour": "blue"}]))

    assert {:ok, [record]} = Json.all(schema)
    assert record[:title] == "Kept"
    assert record["colour"] == "blue"

    {:ok, _updated} = Json.update(schema, 1, %{"done" => true})

    assert {:ok, [written]} = source |> File.read!() |> Jason.decode()
    assert written["colour"] == "blue"
    assert written["done"] == true
  end

  test "inserting casts through the schema, and refuses what will not cast", %{schema: schema} do
    assert {:ok, record} = Json.insert(schema, %{"title" => "x", "priority" => "1"})
    assert record[:priority] == 1

    assert {:error, %Ecto.Changeset{valid?: false} = changeset} =
             Json.insert(schema, %{"priority" => "high"})

    assert Enum.map(ITui.Schema.errors(schema, changeset), fn {f, m} -> {f.name, m} end) ==
             [{"title", "is required"}, {"priority", "must be a whole number"}]

    assert Json.all(schema) == {:ok, [record]}
  end

  test "updating applies the changes onto the record", %{schema: schema} do
    {:ok, record} = Json.insert(schema, %{"title" => "Write it", "priority" => 1})

    assert {:ok, updated} = Json.update(schema, record[:id], %{"done" => true})

    assert updated[:done] == true
    assert updated[:title] == "Write it"
    assert updated[:priority] == 1
    assert updated[:inserted_at] == record[:inserted_at]
  end

  test "getting, and not getting", %{schema: schema} do
    {:ok, record} = Json.insert(schema, %{"title" => "Write it"})

    assert Json.get(schema, record[:id]) == {:ok, record}
    assert Json.get(schema, 99) == {:error, "no todo with id 99"}
    assert Json.update(schema, 99, %{"done" => true}) == {:error, "no todo with id 99"}
    assert Json.delete(schema, 99) == {:error, "no todo with id 99"}
  end

  test "deleting leaves the rest, and does not reuse the id", %{schema: schema} do
    {:ok, first} = Json.insert(schema, %{"title" => "One"})
    {:ok, second} = Json.insert(schema, %{"title" => "Two"})

    assert Json.delete(schema, first[:id]) == :ok
    assert Json.all(schema) == {:ok, [second]}

    assert {:ok, third} = Json.insert(schema, %{"title" => "Three"})
    assert third[:id] == 3
  end

  test "a schema with nowhere to keep records says so", %{schema: schema} do
    schema = %{schema | source: nil}

    assert Json.all(schema) ==
             {:error, ~s(the "todo" schema has no source to read records from)}
  end

  test "a source that is not a list of records says so", %{schema: schema, source: source} do
    File.write!(source, ~s({"not": "a list"}))

    assert {:error, message} = Json.all(schema)
    assert message =~ "expected a list of records"

    File.write!(source, "{oops")
    assert {:error, message} = Json.all(schema)
    assert message =~ "invalid JSON"
  end

  test "ITui.Repo goes through the configured adapter", %{schema: schema} do
    assert ITui.Repo.adapter() == Json
    assert {:ok, record} = ITui.Repo.insert(schema, %{"title" => "Through the facade"})
    assert ITui.Repo.all(schema) == {:ok, [record]}
    assert ITui.Repo.delete(schema, record[:id]) == :ok
  end
end
