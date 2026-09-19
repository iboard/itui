defmodule ITui.CommandTest do
  use ExUnit.Case, async: true
  doctest ITui.Command

  alias ITui.Command

  test "run/1 captures the output of a command that succeeds" do
    assert {:ok, "hello\n"} = Command.run(Command.new("echo", ["hello"]))
  end

  test "run/1 reports a program that is not installed" do
    assert {:error, message} = Command.run(Command.new("i-tui-no-such-program"))
    assert message =~ "command not found"
  end

  test "run/1 reports a non-zero exit, with the command's own output" do
    assert {:error, message} = Command.run(Command.new("sh", ["-c", "echo nope >&2; exit 3"]))
    assert message =~ "exited with status 3"
    assert message =~ "nope"
  end

  describe "render/2" do
    test "fills the placeholders from a record, or from the parameters" do
      command = Command.new("ping", ["-c", "{{count}}", "{{host}}"])

      assert command |> Command.render(%{count: 3, host: "example.com"}) |> Command.to_string() ==
               "ping -c 3 example.com"

      assert command
             |> Command.render(%{"count" => "3", "host" => "example.com"})
             |> Command.to_string() == "ping -c 3 example.com"
    end

    test "a placeholder with nothing to fill it becomes an empty argument" do
      assert Command.new("echo", ["{{nobody_declared_this}}"])
             |> Command.render(%{})
             |> Map.fetch!(:args) == [""]
    end

    test "leaves the program and the fixed arguments alone" do
      assert Command.new("df", ["-h"]) |> Command.render(%{h: "no"}) == Command.new("df", ["-h"])
    end
  end

  test "arguments are passed to the program, not to a shell" do
    assert {:ok, "$HOME\n"} = Command.run(Command.new("echo", ["$HOME"]))
  end
end
