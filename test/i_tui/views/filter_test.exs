defmodule ITui.Views.FilterTest do
  use ITui.UICase, async: false

  alias ITui.Views.Filter

  @bands [{:done, "Done"}, {:overdue, "Overdue"}, {:none, "No due date"}]

  defp start_filter(opts \\ []) do
    start_ui(Filter, Keyword.merge([bands: @bands, counts: %{done: 2, overdue: 1}], opts))
  end

  defp hidden(ui), do: Runtime.view_state(ui, Filter).hidden

  test "lists the kinds, ticked, with how many there are of each" do
    screen = start_filter() |> text()

    assert screen =~ "Show"
    assert screen =~ "[x] Done"
    assert screen =~ "[x] Overdue"
    assert screen =~ "[x] No due date"
    assert screen =~ "2"
    assert screen =~ "esc"
  end

  test "space hides a kind, and shows it again" do
    ui = start_filter()

    assert press(ui, {:char, " "}) =~ "[ ] Done"
    assert hidden(ui) == MapSet.new([:done])

    assert press(ui, {:char, " "}) =~ "[x] Done"
    assert hidden(ui) == MapSet.new()
  end

  test "the arrows move between them" do
    ui = start_filter()

    press(ui, [:down, {:char, " "}])
    assert hidden(ui) == MapSet.new([:overdue])

    press(ui, [{:char, "j"}, {:char, " "}])
    assert hidden(ui) == MapSet.new([:overdue, :none])

    # And around, to the first one.
    press(ui, [:down, {:char, " "}])
    assert hidden(ui) == MapSet.new([:overdue, :none, :done])
  end

  test "it starts from what it was given, and a shows everything again" do
    ui = start_filter(hidden: MapSet.new([:done, :overdue]))
    screen = text(ui)

    assert screen =~ "[ ] Done"
    assert screen =~ "[ ] Overdue"
    assert screen =~ "[x] No due date"

    assert press(ui, {:char, "a"}) =~ "[x] Done"
    assert hidden(ui) == MapSet.new()
  end
end
