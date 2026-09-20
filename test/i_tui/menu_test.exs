defmodule ITui.MenuTest do
  use ExUnit.Case, async: true
  doctest ITui.Menu
  doctest ITui.Menu.Item

  alias ITui.{Command, Menu}
  alias ITui.Menu.Item

  describe "parse/1" do
    test "reads a nested menu" do
      json = """
      {
        "title": "Demo",
        "items": [
          {"key": "s", "label": "System", "items": [
            {"key": "d", "label": "Disk free", "description": "space", "command": "df", "args": ["-h"]}
          ]},
          {"key": "q", "label": "Quit", "action": "quit"}
        ]
      }
      """

      assert {:ok, %Menu{title: "Demo", items: [system, quit]}} = Menu.parse(json)

      assert %Item{key: "s", label: "System", items: [disk]} = system
      assert Item.type(system) == :submenu

      assert %Item{key: "d", description: "space", command: %Command{}} = disk
      assert Command.to_string(disk.command) == "df -h"

      assert %Item{action: :quit} = quit
      assert Item.type(quit) == :action
    end

    test "defaults the title and the arguments" do
      assert {:ok, menu} = Menu.parse(~s({"items": [{"label": "Up", "command": "uptime"}]}))
      assert menu.title == "iTUI"
      assert [%Item{key: nil, command: %Command{args: []}}] = menu.items
    end

    test "rejects invalid JSON" do
      assert {:error, message} = Menu.parse("{nope}")
      assert message =~ "invalid JSON"
    end

    test "rejects a document that is not a menu" do
      assert {:error, ~s(a menu needs an "items" list)} = Menu.parse(~s({"title": "Demo"}))
      assert {:error, message} = Menu.parse("[]")
      assert message =~ "expected a menu object"
    end

    test "names the entry that is wrong, and where it sits" do
      json = ~s({"items": [{"label": "System", "items": [{"command": "df"}]}]})
      assert {:error, message} = Menu.parse(json)
      assert message =~ ~s(in "System": a menu item needs a label)
    end

    test "rejects an entry that does nothing" do
      assert {:error, message} = Menu.parse(~s({"items": [{"label": "Lost"}]}))
      assert message =~ ~s("Lost" does nothing)
    end

    test "rejects an entry that does two things" do
      json = ~s({"items": [{"label": "Both", "command": "df", "action": "quit"}]})
      assert {:error, message} = Menu.parse(json)
      assert message =~ ~s("Both" has more than one of)
    end

    test "rejects an unknown action" do
      assert {:error, message} = Menu.parse(~s({"items": [{"label": "X", "action": "explode"}]}))
      assert message =~ ~s(unknown action "explode")
      assert message =~ "known actions: quit"
    end

    test "rejects a key that is not a single character" do
      json = ~s({"items": [{"key": "qq", "label": "X", "action": "quit"}]})
      assert {:error, message} = Menu.parse(json)
      assert message =~ "must be a single character"
    end

    test "rejects arguments that are not strings" do
      json = ~s({"items": [{"label": "X", "command": "df", "args": [1]}]})
      assert {:error, message} = Menu.parse(json)
      assert message =~ "must be a string"
    end
  end

  describe "load/1" do
    test "reads the menu that ships with the application" do
      assert {:ok, %Menu{title: "iTUI"} = menu} = Menu.load("data/menus/main.json")

      assert [%Item{label: "System"}, %Item{label: "Todos", view: "todo"}, %Item{action: :quit}] =
               menu.items

      assert menu.items
             |> hd()
             |> Map.fetch!(:items)
             |> Enum.map(&Command.to_string(&1.command)) == [
               "df -h",
               "uptime",
               "free -h",
               "ping -c {{count}} {{host}}"
             ]

      assert menu.items |> hd() |> Map.fetch!(:items) |> List.last() |> Map.fetch!(:form) ==
               "ping"
    end

    test "defaults to the configured menu file" do
      assert Menu.default_path() == "data/menus/main.json"
      assert {:ok, %Menu{}} = Menu.load()
    end

    test "reports a file it cannot read" do
      assert {:error, message} = Menu.load("data/menus/nope.json")
      assert message =~ "data/menus/nope.json: no such file or directory"
    end
  end

  test "find_by_key/2 ignores entries without a key" do
    {:ok, menu} = Menu.parse(~s({"items": [{"label": "Up", "command": "uptime"}]}))

    assert Menu.find_by_key(menu.items, "u") == nil
  end

  describe "resolve/2" do
    @menu """
    {"items": [
      {"key": "s", "label": "System", "items": [
        {"key": "d", "label": "Disk free", "command": "df"},
        {"key": "u", "label": "Uptime", "command": "uptime"},
        {"key": "m", "label": "Disk mounts", "command": "mount"}
      ]},
      {"key": "t", "label": "Todos", "view": "todo"}
    ]}
    """

    setup do
      {:ok, menu} = Menu.parse(@menu)

      %{items: menu.items}
    end

    defp labels(items, path) do
      with {:ok, chain} <- Menu.resolve(items, path), do: Enum.map(chain, & &1.label)
    end

    test "walks the keys of the entries", %{items: items} do
      assert labels(items, ["s", "u"]) == ["System", "Uptime"]
    end

    test "walks their labels, however they are written", %{items: items} do
      assert labels(items, ["System", "Uptime"]) == ["System", "Uptime"]
      assert labels(items, ["system", "disk-free"]) == ["System", "Disk free"]
      assert labels(items, ["SYSTEM", "Disk Free"]) == ["System", "Disk free"]
    end

    test "as much of a label as says which one it is will do", %{items: items} do
      assert labels(items, ["sys", "up"]) == ["System", "Uptime"]
    end

    test "a path of nothing is no path at all", %{items: items} do
      assert Menu.resolve(items, []) == {:ok, []}
    end

    test "a beginning that fits more than one is a question, not an answer", %{items: items} do
      assert {:error, message} = Menu.resolve(items, ["system", "disk"])
      assert message == ~s("disk" could be any of: Disk free, Disk mounts)
    end

    test "says what there is when there is no such entry", %{items: items} do
      assert Menu.resolve(items, ["files"]) ==
               {:error, ~s(there is no "files" in the menu; there is: System, Todos)}

      assert Menu.resolve(items, ["system", "files"]) ==
               {:error,
                ~s(there is no "files" in "System"; there is: Disk free, Uptime, Disk mounts)}
    end

    test "refuses to go on past an entry with nothing in it", %{items: items} do
      assert Menu.resolve(items, ["todos", "first"]) ==
               {:error, ~s("Todos" has nothing in it, so there is no "first" in it)}
    end
  end
end
