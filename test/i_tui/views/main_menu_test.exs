defmodule ITui.Views.MainMenuTest do
  use ITui.UICase, async: false

  alias ITui.Menu
  alias ITui.Views.{MainMenu, Output}

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

      assert screen =~ "Test 0.1.0"
      assert screen =~ "▸ s  System"
      assert screen =~ "q  Quit"
      assert screen =~ "2 entries →"
      assert screen =~ "↑↓ move · enter run · q quit"
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
