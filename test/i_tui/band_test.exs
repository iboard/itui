defmodule ITui.BandTest do
  use ExUnit.Case, async: true
  doctest ITui.Band

  alias ITui.{Band, Schema}

  @schema ~s({"name": "todo", "fields": [
    {"name": "due", "type": "date"},
    {"name": "done", "type": "boolean"}
  ]})

  setup do
    {:ok, schema} = Schema.parse(@schema)

    # A Monday, so that there is a week left of the week and a fortnight
    # left of the month — room enough to tell every band apart.
    %{schema: schema, today: ~D[2026-09-14]}
  end

  defp band(context, todo), do: Band.of(context.schema, todo, context.today)

  test "a ticked todo is done, whenever it was due", context do
    assert band(context, %{done: true, due: "2020-01-01"}) == :done
    assert band(context, %{done: true}) == :done
  end

  test "the rest are placed by how near the day is", context do
    assert band(context, %{due: "2026-09-13"}) == :overdue
    assert band(context, %{due: "2026-09-14"}) == :soon
    assert band(context, %{due: "2026-09-16"}) == :soon
    assert band(context, %{due: "2026-09-17"}) == :week
    assert band(context, %{due: "2026-09-20"}) == :week
    assert band(context, %{due: "2026-09-21"}) == :month
    assert band(context, %{due: "2026-09-30"}) == :month
    assert band(context, %{due: "2026-10-01"}) == :later
  end

  test "a todo that is due on no particular day is none of them", context do
    assert band(context, %{due: nil}) == :none
    assert band(context, %{}) == :none
  end

  test "so is every todo of a schema with no due date", context do
    {:ok, schema} = Schema.parse(~s({"name": "note", "fields": [{"name": "title"}]}))

    assert Band.of(schema, %{due: "2020-01-01"}, context.today) == :none
  end

  test "the names are the bands, in the order the ladder goes" do
    assert Band.names() == Enum.map(Band.list(), fn {band, _label} -> Atom.to_string(band) end)
  end
end
