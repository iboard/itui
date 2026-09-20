defmodule ITui.Views.MainMenuTest do
  use ITui.UICase, async: false

  alias ITui.Menu
  alias ITui.Views.{About, Form, MainMenu, Output, Todo}

  @menu """
  {
    "title": "Test",
    "items": [
      {"key": "s", "label": "System", "items": [
        {"key": "e", "label": "Echo", "description": "prints a line",
         "command": "echo", "args": ["a line of output"]},
        {"key": "b", "label": "Broken", "command": "i-tui-no-such-program"}
      ]},
      {"key": "f", "label": "Files", "items": [
        {"key": "p", "label": "Working directory", "command": "pwd"}
      ]},
      {"key": "w", "label": "Echo a word", "command": "echo", "args": ["{{word}}"],
       "form": "test/fixtures/word.json"},
      {"key": "t", "label": "Todos", "view": "todo"},
      {"key": "q", "label": "Quit", "action": "quit"}
    ]
  }
  """

  setup do
    {:ok, menu} = Menu.parse(@menu)

    %{ui: start_ui(MainMenu, menu: menu)}
  end

  defp cursor(ui), do: Runtime.view_state(ui, MainMenu).cursor

  describe "the menu" do
    test "draws the entries of the top level", %{ui: ui} do
      screen = text(ui)

      assert screen =~ "Test #{ITui.version()}"
      assert screen =~ "▸ s  System"
      assert screen =~ "q  Quit"
      assert screen =~ "2 entries →"
      assert screen =~ "↑↓ move · enter run · ? about · q quit"
    end

    test "shows the description of the entry under the cursor", %{ui: ui} do
      assert press(ui, {:char, "s"}) =~ "prints a line"
      refute press(ui, :down) =~ "prints a line"
    end

    test "moves the cursor, and wraps around", %{ui: ui} do
      assert press(ui, :down) =~ "▸ f  Files"
      assert cursor(ui) == 1

      assert press(ui, :end) =~ "▸ q  Quit"
      assert press(ui, :down) =~ "▸ s  System"
      assert cursor(ui) == 0

      assert press(ui, {:char, "k"}) =~ "▸ q  Quit"
    end
  end

  describe "submenus" do
    test "enter descends into the entry under the cursor", %{ui: ui} do
      screen = press(ui, :enter)

      assert screen =~ "Test › System"
      assert screen =~ "▸ e  Echo"
      assert screen =~ "echo a line of output"
      assert screen =~ "esc back"
    end

    test "an entry's own key opens it, moving the cursor there first", %{ui: ui} do
      assert press(ui, {:char, "f"}) =~ "Test › Files"
      assert text(ui) =~ "▸ p  Working directory"

      # Coming back lands on Files, not on the entry the cursor started on.
      assert press(ui, :esc) =~ "▸ f  Files"
      assert cursor(ui) == 1
    end

    test "esc at the top level does nothing", %{ui: ui} do
      assert press(ui, :esc) =~ "▸ s  System"
      assert Runtime.view_stack(ui) == [MainMenu]
    end
  end

  describe "running a command" do
    test "shows what it printed, and what was run", %{ui: ui} do
      press(ui, [{:char, "s"}, {:char, "e"}])

      screen = await_view(ui, Output)

      assert screen =~ "Echo"
      assert screen =~ "echo a line of output"
      assert screen =~ "a line of output"
      assert screen =~ "esc close"
    end

    test "shows why a command did not run", %{ui: ui} do
      press(ui, [{:char, "s"}, {:char, "b"}])

      assert await_view(ui, Output) =~ "command not found: i-tui-no-such-program"
    end

    test "the popup owns the keyboard while it is open", %{ui: ui} do
      press(ui, [{:char, "s"}, {:char, "e"}])
      await_view(ui, Output)

      at = cursor(ui)
      press(ui, [:down, :down])

      assert cursor(ui) == at
    end

    test "esc closes it and hands the keys back to the menu", %{ui: ui} do
      press(ui, [{:char, "s"}, {:char, "e"}])
      await_view(ui, Output)

      screen = press(ui, :esc)

      assert Runtime.view_stack(ui) == [MainMenu]
      assert screen =~ "Test › System"
      assert press(ui, :down) =~ "▸ b  Broken"
    end
  end

  describe "an entry that asks for its arguments" do
    test "opens the form, then runs the command with what it collected", %{ui: ui} do
      assert press(ui, {:char, "w"}) =~ "Echo a word"
      assert Runtime.view_stack(ui) == [Form, MainMenu]

      type(ui, "supercalifragilistic")
      press(ui, :enter)

      assert await_view(ui, Output) =~ "supercalifragilistic"
      assert text(ui) =~ "echo supercalifragilistic"
    end

    test "a form that was cancelled runs nothing", %{ui: ui} do
      press(ui, {:char, "w"})
      press(ui, :esc)

      assert settle(ui) =~ "▸ w  Echo a word"
      assert Runtime.view_stack(ui) == [MainMenu]
      assert Runtime.view_state(ui, MainMenu).busy == nil
    end
  end

  describe "an entry that opens an application" do
    test "pushes the view, and takes the keys back when it closes", %{ui: ui} do
      assert press(ui, {:char, "t"}) =~ "Todos"
      assert Runtime.view_stack(ui) == [Todo, MainMenu]

      press(ui, :esc)
      assert settle(ui) =~ "▸ t  Todos"
      assert Runtime.view_stack(ui) == [MainMenu]

      # The menu is listening again, rather than passing everything on.
      assert press(ui, :home) =~ "▸ s  System"
    end
  end

  describe "the about popup" do
    test "? opens it, and esc gives the keys back", %{ui: ui} do
      screen = press(ui, {:char, "?"})

      assert Runtime.view_stack(ui) == [About, MainMenu]
      assert screen =~ "iTUI #{ITui.version()}"
      assert screen =~ "GPL-3.0-or-later"

      press(ui, :esc)
      assert settle(ui) =~ "▸ s  System"
      assert Runtime.view_stack(ui) == [MainMenu]
      assert press(ui, :down) =~ "▸ f  Files"
    end

    test "the menu says the key is there", %{ui: ui} do
      assert text(ui) =~ "? about"
    end
  end

  describe "quitting" do
    test "q stops the UI", %{ui: ui} do
      ref = Process.monitor(ui)
      Runtime.send_key(ui, {:char, "q"})

      assert_receive {:DOWN, ^ref, :process, ^ui, :normal}, 1_000
    end

    test "the quit entry stops the UI too", %{ui: ui} do
      ref = Process.monitor(ui)
      Runtime.send_key(ui, :end)
      Runtime.send_key(ui, :enter)

      assert_receive {:DOWN, ^ref, :process, ^ui, :normal}, 1_000
    end
  end
end

defmodule ITui.Views.MainMenuFileTest do
  use ITui.UICase, async: false

  alias ITui.Views.MainMenu

  test "the menu that ships with the application is the one that is drawn" do
    ui = start_ui(MainMenu)

    assert text(ui) =~ "▸ s  System"
    assert press(ui, :enter) =~ "df -h"
  end

  test "a menu file that cannot be read is reported, not fatal" do
    ui = start_ui(MainMenu, path: "data/menus/nope.json")
    screen = text(ui)

    assert screen =~ "no such file or directory"
    assert screen =~ "the menu could not be loaded"
  end
end

defmodule ITui.Views.MainMenuMissingTest do
  use ITui.UICase, async: false

  alias ITui.Menu
  alias ITui.Views.{MainMenu, Output}

  @menu """
  {"items": [
    {"key": "v", "label": "Ghost", "view": "spreadsheet"},
    {"key": "f", "label": "No form", "command": "echo", "form": "nonexistent"}
  ]}
  """

  setup do
    {:ok, menu} = Menu.parse(@menu)

    %{ui: start_ui(MainMenu, menu: menu)}
  end

  test "an entry naming a view that does not exist says so", %{ui: ui} do
    screen = press(ui, {:char, "v"})

    assert Runtime.view_stack(ui) == [Output, MainMenu]
    assert screen =~ ~s(unknown view "spreadsheet")
    assert screen =~ "known views: todo"
  end

  test "an entry naming a form that is not there says so", %{ui: ui} do
    screen = press(ui, {:char, "f"})

    assert screen =~ "data/schemas/nonexistent.json: no such file or directory"
  end
end

defmodule ITui.Views.MainMenuOpenTest do
  @moduledoc """
  The menu opened somewhere in particular, as the command line asks for it.

  A module of its own: every one of these starts a UI of its own, and the
  runtime registers itself under its own name.
  """

  use ITui.UICase, async: false

  alias ITui.Menu
  alias ITui.Views.{Form, MainMenu, Output, Todo}

  @menu """
  {
    "title": "Test",
    "items": [
      {"key": "s", "label": "System", "items": [
        {"key": "e", "label": "Echo", "command": "echo", "args": ["a line of output"]}
      ]},
      {"key": "f", "label": "Files", "items": [
        {"key": "p", "label": "Working directory", "command": "pwd"}
      ]},
      {"key": "w", "label": "Echo a word", "command": "echo", "args": ["{{word}}"],
       "form": "test/fixtures/word.json"},
      {"key": "t", "label": "Todos", "view": "todo"}
    ]
  }
  """

  setup do
    {:ok, menu} = Menu.parse(@menu)

    %{menu: menu}
  end

  test "a path walks down to the entry and does what enter does", %{menu: menu} do
    ui = start_ui(MainMenu, menu: menu, open: ["system", "echo"])

    assert await_view(ui, Output) =~ "a line of output"

    # And the menu underneath is where the path left it.
    press(ui, :esc)
    assert settle(ui) =~ "Test › System"
  end

  test "a path that stops at a submenu opens it", %{menu: menu} do
    ui = start_ui(MainMenu, menu: menu, open: ["f"])

    assert text(ui) =~ "Test › Files"
    assert text(ui) =~ "▸ p  Working directory"
    assert press(ui, :esc) =~ "▸ f  Files"
  end

  test "an entry that asks for its arguments still asks", %{menu: menu} do
    ui = start_ui(MainMenu, menu: menu, open: ["echo-a-word"])

    assert await_view(ui, Form) =~ "Echo a word"
  end

  test "a path that is not in the menu says so, rather than doing nothing", %{menu: menu} do
    ui = start_ui(MainMenu, menu: menu, open: ["system", "nonsense"])

    assert await_view(ui, Output) =~ ~s(there is no "nonsense" in "System")
  end

  test "a view is opened by name, whether or not the menu has an entry for it",
       %{menu: menu} do
    ui = start_ui(MainMenu, menu: menu, open_view: "todo")

    assert await_view(ui, Todo) =~ "Todos"

    press(ui, :esc)
    assert settle(ui) =~ "▸ s  System"
    assert Runtime.view_stack(ui) == [MainMenu]
  end

  test "a view that is not one says what there is", %{menu: menu} do
    ui = start_ui(MainMenu, menu: menu, open_view: "spreadsheet")

    assert await_view(ui, Output) =~ ~s(unknown view "spreadsheet")
  end
end
