defmodule ITui.CLITest do
  use ExUnit.Case, async: false

  alias ITui.{CLI, Repo, Schema}

  # The data directory is said outright, so the commands that read one read a
  # directory of this test's own — installed from the files iTUI ships with,
  # which is what they would find on a first run.
  setup do
    dir = Path.join(System.tmp_dir!(), "i_tui_cli_#{System.unique_integer([:positive])}")
    configured = Application.get_env(:i_tui, :data_dir)
    System.put_env("ITUI_DATA", dir)

    on_exit(fn ->
      System.delete_env("ITUI_DATA")
      Application.put_env(:i_tui, :data_dir, configured)
      File.rm_rf(dir)
    end)

    %{dir: dir}
  end

  describe "saying what it is" do
    test "no arguments open the menu" do
      assert CLI.command([]) == {:open, []}
    end

    test "--version says the version of the project" do
      assert CLI.command(["--version"]) == {:say, "iTUI #{Mix.Project.config()[:version]}"}
      assert CLI.command(["-v"]) == CLI.command(["--version"])
    end

    test "--where says the data directory, and writes it out", %{dir: dir} do
      assert CLI.command(["--where"]) == {:say, dir}

      assert File.exists?(Path.join(dir, "menus/main.json"))
      assert File.exists?(Path.join(dir, "schemas/todo.json"))
    end

    test "--help says all of it, with the fields of the todo schema" do
      assert {:say, help} = CLI.command(["--help"])

      assert help =~ "itui menu PATH"
      assert help =~ "itui todo list"
      assert help =~ "itui todo done NUMBER"
      assert help =~ "done · overdue · soon · week · month · later · none"
      assert help =~ "--title TEXT"
      assert help =~ "--due DAY"
      assert help =~ "--done "
      assert help =~ "Priority — 1 is highest"
    end

    test "anything else is refused, and said back" do
      assert CLI.command(["frobnicate"]) ==
               {:error, ~s(I do not know what to do with "frobnicate")}
    end
  end

  describe "itui menu" do
    test "with no path, it is the menu as it opens" do
      assert CLI.command(["menu"]) == {:open, []}
    end

    test "a path is passed to the view that walks it" do
      assert CLI.command(["menu", "system/uptime"]) == {:open, [open: ["system", "uptime"]]}
    end

    test "the segments may be words instead of one path" do
      assert CLI.command(["menu", "system", "uptime"]) == {:open, [open: ["system", "uptime"]]}
    end

    test "the keys of the entries will do, and so will the start of a name" do
      assert CLI.command(["menu", "s/u"]) == {:open, [open: ["s", "u"]]}
      assert CLI.command(["menu", "system/disk-free"]) == {:open, [open: ["system", "disk-free"]]}
    end

    # Resolved before the UI is started: a name that is not in the menu is a
    # line on the terminal rather than a popup over one.
    test "a name the menu does not have is refused, with what it does have" do
      assert {:error, message} = CLI.command(["menu", "nonsense"])

      assert message =~ ~s(there is no "nonsense" in the menu)
      assert message =~ "System, Todos, Quit"
    end

    test "a name a submenu does not have says which submenu" do
      assert {:error, message} = CLI.command(["menu", "system/nonsense"])

      assert message =~ ~s(there is no "nonsense" in "System")
      assert message =~ "Disk free, Uptime, Memory"
    end
  end

  describe "itui todo" do
    test "on its own, it opens the todo list" do
      assert CLI.command(["todo"]) == {:open, [open_view: "todo"]}
    end

    test "add stores one in the records of the data directory", %{dir: dir} do
      assert CLI.command(["todo", "add", "Buy milk", "--due", "2026-12-24"]) ==
               {:say, "added #1 Buy milk"}

      assert {:ok, schema} = Schema.load("todo")
      assert {:ok, [%{title: "Buy milk", due: "2026-12-24"}]} = Repo.all(schema)
      assert File.exists?(Path.join(dir, "records/todos.json"))
    end

    test "done checks one off, and list prints what is left" do
      {:say, _said} = CLI.command(["todo", "add", "Buy milk"])
      {:say, _said} = CLI.command(["todo", "add", "Write the docs"])

      assert CLI.command(["todo", "done", "1"]) == {:say, "checked off #1 Buy milk"}

      assert {:say, printed} = CLI.command(["todo", "list", "--hide", "done"])
      assert printed =~ "Write the docs"
      refute printed =~ "Buy milk"
    end

    test "anything else is refused, with what it takes" do
      assert {:error, message} = CLI.command(["todo", "finish", "1"])

      assert message =~ ~s(I do not know what "finish 1" means)
      assert message =~ "it takes list, add and done"
    end
  end
end
