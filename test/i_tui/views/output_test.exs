defmodule ITui.Views.OutputTest do
  use ITui.UICase, async: false

  alias ITui.Views.Output

  @lines 1..40
         |> Enum.map(&"line #{String.pad_leading(to_string(&1), 2, "0")}")
         |> Enum.join("\n")

  defp start_output(opts) do
    start_ui(Output, Keyword.merge([title: "Echo", subtitle: "echo hi", size: {40, 12}], opts))
  end

  test "shows the title, the command and the output" do
    screen = start_output(result: {:ok, "one\ntwo\n"}) |> text()

    assert screen =~ "Echo"
    assert screen =~ "echo hi"
    assert screen =~ "one"
    assert screen =~ "two"
    assert screen =~ "esc close"
  end

  test "says so when a command printed nothing" do
    assert start_output(result: {:ok, ""}) |> text() =~ "(no output)"
  end

  test "a popup as wide as its output says more in its footer" do
    wide = Enum.map_join(1..40, "\n", &(String.duplicate("x", 50) <> " #{&1}"))
    ui = start_ui(Output, title: "Echo", result: {:ok, wide}, size: {80, 12})

    assert text(ui) =~ "esc close · ↑↓ scroll · 1-7 of 40"
  end

  test "a line wider than the terminal is cut, not drawn over the border" do
    ui =
      start_ui(Output, title: "Echo", result: {:ok, String.duplicate("x", 200)}, size: {40, 12})

    for line <- ui |> text() |> String.split("\r\n"), line =~ "x" do
      assert line =~ ~r/│ x{32} │/
    end
  end

  test "shows an error where the output would be" do
    assert start_output(result: {:error, "command not found: nope"}) |> text() =~
             "not found: nope"
  end

  describe "scrolling" do
    setup do
      %{ui: start_output(result: {:ok, @lines})}
    end

    test "starts at the top", %{ui: ui} do
      screen = text(ui)

      assert screen =~ "line 01"
      assert screen =~ "1-5/40"
      refute screen =~ "line 06"
    end

    test "moves a line at a time", %{ui: ui} do
      screen = press(ui, :down)

      assert screen =~ "2-6/40"
      refute screen =~ "line 01"

      assert press(ui, :up) =~ "1-5/40"
    end

    test "moves a page at a time", %{ui: ui} do
      assert press(ui, :page_down) =~ "11-15/40"
      assert press(ui, :page_up) =~ "1-5/40"
    end

    test "stops at both ends", %{ui: ui} do
      assert press(ui, :up) =~ "1-5/40"

      # The last line can sit at the top of the body, and no further.
      assert press(ui, :end) =~ "40-40/40"
      assert press(ui, :down) =~ "40-40/40"
      assert press(ui, :home) =~ "1-5/40"
    end
  end
end
