defmodule ITui.DataTest do
  use ExUnit.Case, async: false

  alias ITui.Data

  setup do
    # The environment decides where the data lives, so a test that asks must
    # put back what it found.
    was = {System.get_env("ITUI_DATA"), Application.get_env(:i_tui, :data_dir)}

    on_exit(fn ->
      {said, dir} = was

      if said, do: System.put_env("ITUI_DATA", said), else: System.delete_env("ITUI_DATA")
      Application.put_env(:i_tui, :data_dir, dir)
    end)

    home = Path.join(System.tmp_dir!(), "i_tui_home_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(home) end)

    %{home: home}
  end

  test "carries the menus and schemas that ship with it" do
    bundled = Data.bundled()

    assert Map.has_key?(bundled, "menus/main.json")
    assert Map.has_key?(bundled, "schemas/todo.json")

    assert {:ok, %{"items" => _items}} =
             bundled |> Map.fetch!("menus/main.json") |> Jason.decode()

    # Records are somebody's own; only the files that describe the application.
    refute Enum.any?(Map.keys(bundled), &String.starts_with?(&1, "records/"))
  end

  test "writes them where it was told, and never over one that is there", %{home: home} do
    System.put_env("ITUI_DATA", home)

    assert Data.resolve!() == home
    assert Data.dir() == home
    assert File.read!(Path.join(home, "schemas/todo.json")) == Data.bundled()["schemas/todo.json"]

    File.write!(Path.join(home, "menus/main.json"), ~s({"items": []}))
    assert Data.install!(home) == []
    assert File.read!(Path.join(home, "menus/main.json")) == ~s({"items": []})
  end

  test "a schema's source is a path inside it", %{home: home} do
    System.put_env("ITUI_DATA", home)
    Data.resolve!()

    assert Data.path("records/todos.json") == Path.join(home, "records/todos.json")
    assert Data.path("/tmp/elsewhere.json") == "/tmp/elsewhere.json"
  end

  test "the shipped menu and schemas are the ones it carries" do
    for {path, contents} <- Data.bundled() do
      assert File.read!(Path.join("data", path)) == contents
      assert {:ok, _decoded} = Jason.decode(contents)
    end
  end
end
