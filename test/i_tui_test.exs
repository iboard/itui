defmodule ITuiTest do
  use ExUnit.Case, async: true
  doctest ITui

  test "version/0 returns the mix project version" do
    assert ITui.version() == Mix.Project.config()[:version]
  end
end
