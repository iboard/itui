defmodule ITui.TextAreaTest do
  use ExUnit.Case, async: true
  doctest ITui.TextArea

  alias Atui.{Rect, Screen}
  alias ITui.TextArea

  defp area(value \\ ""), do: TextArea.new(value: value)

  defp press(area, keys) do
    Enum.reduce(keys, area, fn key, acc ->
      case TextArea.handle_key(acc, key) do
        {:ok, area} -> area
        {:pass, area} -> area
      end
    end)
  end

  defp type(area, text), do: press(area, Enum.map(String.graphemes(text), &{:char, &1}))

  defp drawn(area, width, height) do
    Screen.new(width, height)
    |> TextArea.draw(area, Rect.sized(width, height))
    |> Screen.to_text()
    |> String.split("\r\n")
  end

  test "starts empty, and takes what it is given" do
    assert TextArea.value(area()) == ""
    assert TextArea.empty?(area())

    area = area("one\ntwo")
    assert TextArea.value(area) == "one\ntwo"
    refute TextArea.empty?(area)

    # The cursor starts after the text, which is the end of the last line.
    assert {area.row, area.col} == {1, 3}
  end

  test "typing inserts at the cursor" do
    assert area() |> type("hello") |> TextArea.value() == "hello"

    assert area("ac") |> press([:home, :right]) |> type("b") |> TextArea.value() == "abc"
  end

  test "enter starts a new line" do
    area = area() |> type("one") |> press([:enter]) |> type("two")

    assert TextArea.value(area) == "one\ntwo"
    assert {area.row, area.col} == {1, 3}

    # And in the middle of a line, it takes the rest of it along.
    area = area("onetwo") |> press([:home, :right, :right, :right, :enter])
    assert TextArea.value(area) == "one\ntwo"
  end

  test "backspace joins a line to the one before it" do
    area = area("one\ntwo") |> press([:home, :backspace])

    assert TextArea.value(area) == "onetwo"
    assert {area.row, area.col} == {0, 3}

    # At the very start there is nothing to join.
    assert area("one") |> press([:home, :backspace]) |> TextArea.value() == "one"
    assert area("abc") |> press([:backspace]) |> TextArea.value() == "ab"
  end

  test "delete takes the character in front, and the line after" do
    assert area("abc") |> press([:home, :delete]) |> TextArea.value() == "bc"
    assert area("one\ntwo") |> press([:up, :end, :delete]) |> TextArea.value() == "onetwo"
    assert area("one") |> press([:end, :delete]) |> TextArea.value() == "one"
  end

  test "the sideways arrows walk across the line endings" do
    area = area("ab\ncd") |> press([:home])
    assert {area.row, area.col} == {1, 0}

    area = press(area, [:left])
    assert {area.row, area.col} == {0, 2}

    area = press(area, [:right])
    assert {area.row, area.col} == {1, 0}

    # And they stop at both ends.
    assert area("ab") |> press([:home, :left]) |> Map.take([:row, :col]) == %{row: 0, col: 0}
    assert area("ab") |> press([:right]) |> Map.take([:row, :col]) == %{row: 0, col: 2}
  end

  test "the vertical arrows move between lines, and out at the edges" do
    area = area("one\ntwo\nthree")

    assert {:ok, area} = TextArea.handle_key(area, :up)
    assert area.row == 1

    assert {:ok, area} = TextArea.handle_key(area, :up)
    assert area.row == 0

    # At the top and the bottom they belong to whoever holds the field.
    assert {:pass, ^area} = TextArea.handle_key(area, :up)

    area = press(area, [:down, :down])
    assert {:pass, ^area} = TextArea.handle_key(area, :down)
  end

  test "moving up keeps the column where the line is long enough" do
    area = area("longer line\nab") |> press([:end, :up])

    assert {area.row, area.col} == {0, 2}
  end

  test "home, end and the kill keys work on the line the cursor is on" do
    assert area("one\ntwo") |> press([:home]) |> Map.fetch!(:col) == 0
    assert area("one\ntwo") |> press([:home, :end]) |> Map.fetch!(:col) == 3

    assert area("one\ntwo") |> press([:home, {[:ctrl], "e"}]) |> Map.fetch!(:col) == 3
    assert area("one\ntwo") |> press([{[:ctrl], "a"}]) |> Map.fetch!(:col) == 0

    assert area("one\ntwo") |> press([:home, :right, {[:ctrl], "k"}]) |> TextArea.value() ==
             "one\nt"

    assert area("one\ntwo") |> press([{[:ctrl], "u"}]) |> TextArea.value() == "one\n"
  end

  test "tab and esc are never claimed" do
    area = area("one")

    assert {:pass, ^area} = TextArea.handle_key(area, :tab)
    assert {:pass, ^area} = TextArea.handle_key(area, :esc)
  end

  test "into/3 puts the field back where the host keeps it" do
    state = %{area: area("one")}

    assert {:ok, %{area: area}} =
             state.area |> TextArea.handle_key({:char, "!"}) |> TextArea.into(state)

    assert TextArea.value(area) == "one!"
  end

  describe "drawing" do
    test "puts one line per row, with the cursor as a reversed cell" do
      lines = area("one\ntwo") |> drawn(10, 3)

      assert Enum.at(lines, 0) == "one       "
      assert Enum.at(lines, 1) == "two       "
    end

    test "shows the placeholder while there is nothing in it" do
      area = TextArea.new(placeholder: "say something")

      assert area |> drawn(20, 2) |> Enum.at(0) == "say something       "
    end

    test "scrolls to keep the cursor in view" do
      area = area("one\ntwo\nthree\nfour")

      # The cursor is on the last line, so that is the one at the bottom.
      assert area |> TextArea.window(Rect.sized(10, 2)) == ["three", "four"]

      assert area |> press([:up, :up, :up]) |> TextArea.window(Rect.sized(10, 2)) == [
               "one",
               "two"
             ]
    end

    test "long lines scroll sideways with the cursor" do
      area = area("a very long line indeed")

      assert area |> TextArea.window(Rect.sized(10, 1)) == ["ne indeed"]
      assert area |> press([:home]) |> TextArea.window(Rect.sized(10, 1)) == ["a very lon"]
    end

    test "draws nothing into no room at all" do
      assert Screen.new(4, 1) |> TextArea.draw(area("x"), Rect.sized(0, 0)) |> Screen.to_text() ==
               "    "
    end
  end
end
