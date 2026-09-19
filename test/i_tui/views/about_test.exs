defmodule ITui.Views.AboutTest do
  use ITui.UICase, async: false

  alias ITui.Views.About

  test "says what this is and what it is built on" do
    screen = About |> start_ui(size: {70, 20}) |> text()

    assert screen =~ "About"
    assert screen =~ "iTUI #{ITui.version()}"
    assert screen =~ "A configurable terminal UI for Linux"
    assert screen =~ "ATUI #{Atui.version()}"
    assert screen =~ "Elixir #{System.version()}"
    assert screen =~ "github.com/iboard/itui"
    assert screen =~ "GPL-3.0-or-later"
    assert screen =~ "esc close"
  end

  test "fits inside a small terminal" do
    screen = About |> start_ui(size: {40, 12}) |> text()

    assert screen =~ "iTUI"
    refute screen |> String.split("\r\n") |> Enum.any?(&(String.length(&1) > 40))
  end
end
