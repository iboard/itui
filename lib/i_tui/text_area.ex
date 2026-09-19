defmodule ITui.TextArea do
  @moduledoc """
  A field of several lines, in the shape of `Atui.TextInput`.

  A struct the host keeps in its state, offers keys to, and draws into a block
  of its own screen. It owns no process and no part of the screen, so a form
  can put one wherever it has the rows to spare.

      iex> area = ITui.TextArea.new(value: "one\\ntwo")
      iex> {:ok, area} = ITui.TextArea.handle_key(area, {:char, "!"})
      iex> ITui.TextArea.value(area)
      "one\\ntwo!"

  ## Which keys it claims

  The printable characters, `enter` for a new line, and the editing keys:
  backspace and delete either side of the cursor (which join lines at the
  ends), `←` `→` across lines, Home, End, Ctrl-A, Ctrl-E, Ctrl-K and Ctrl-U.

  `↑` and `↓` move between the lines it has — but at the top and the bottom it
  passes them on, so the arrows walk out of the field and into the rest of the
  form rather than trapping the cursor. Tab and ESC are never claimed.

  ## The cursor, and what is on screen

  Like `Atui.TextInput`, the cursor is a reversed cell rather than the
  terminal's own, so the field can be drawn anywhere. The lines scroll
  vertically to keep the cursor in view, and long lines scroll sideways
  together — both are a pure function of the value, the cursor and the size,
  so nothing about scrolling is kept in the struct.
  """

  alias Atui.{Rect, Screen, Style}

  defstruct lines: [""], row: 0, col: 0, placeholder: ""

  @type t :: %__MODULE__{
          lines: [String.t()],
          row: non_neg_integer(),
          col: non_neg_integer(),
          placeholder: String.t()
        }

  @type reply :: {:ok, t()} | {:pass, t()}

  @doc """
  Builds a field.

  Options: `:value` — the initial text, newlines and all, with the cursor after
  it — and `:placeholder`, what to draw while there is nothing in it.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    opts
    |> Keyword.get(:value, "")
    |> then(&put_value(%__MODULE__{placeholder: Keyword.get(opts, :placeholder, "")}, &1))
  end

  @doc "The text in the field, lines joined by newlines."
  @spec value(t()) :: String.t()
  def value(%__MODULE__{lines: lines}), do: Enum.join(lines, "\n")

  @doc "Replaces the text, putting the cursor at the end of it."
  @spec put_value(t(), String.t()) :: t()
  def put_value(%__MODULE__{} = area, text) when is_binary(text) do
    lines = String.split(text, "\n")
    row = length(lines) - 1

    %{area | lines: lines, row: row, col: length(graphemes(Enum.at(lines, row)))}
  end

  @doc "True while there is nothing in the field."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{lines: [""]}), do: true
  def empty?(%__MODULE__{}), do: false

  @doc """
  Handles a key, answering `{:pass, area}` for the ones it does not claim.
  """
  @spec handle_key(t(), Atui.Key.t()) :: reply()
  def handle_key(%__MODULE__{} = area, key), do: press(area, key)

  @doc """
  Rewrites a reply about the field into a reply about the state holding it.
  """
  @spec into(reply(), map(), atom()) :: {:ok | :pass, map()}
  def into(reply, state, key \\ :area)

  def into({kind, %__MODULE__{} = area}, state, key) when kind in [:ok, :pass] do
    {kind, Map.put(state, key, area)}
  end

  @doc """
  Draws the field into `rect`, as many lines as it has room for.

  Options: `:style`, `:placeholder_style`, `:cursor_style` and `:focus`
  (default `true`) — the same as `Atui.TextInput.draw/4`.
  """
  @spec draw(Screen.t(), t(), Rect.t(), keyword()) :: Screen.t()
  def draw(screen, area, rect, opts \\ [])

  def draw(screen, _area, %Rect{width: width, height: height}, _opts)
      when width <= 0 or height <= 0,
      do: screen

  def draw(%Screen{} = screen, %__MODULE__{} = area, %Rect{} = rect, opts) do
    focus? = Keyword.get(opts, :focus, true)
    style = Keyword.get(opts, :style)

    if empty?(area) and area.placeholder != "" do
      screen
      |> Screen.put_text(
        rect.x,
        rect.y,
        Screen.truncate(area.placeholder, rect.width),
        Keyword.get(opts, :placeholder_style, style)
      )
      |> cursor(area, rect, opts, focus?)
    else
      area
      |> window(rect)
      |> Enum.with_index(rect.y)
      |> Enum.reduce(screen, fn {line, y}, acc -> Screen.put_text(acc, rect.x, y, line, style) end)
      |> cursor(area, rect, opts, focus?)
    end
  end

  @doc """
  The lines to draw, clipped to `rect` — the window that keeps the cursor in
  view, vertically and sideways.
  """
  @spec window(t(), Rect.t()) :: [String.t()]
  def window(%__MODULE__{} = area, %Rect{} = rect) do
    area.lines
    |> Enum.slice(top(area, rect.height), rect.height)
    |> Enum.map(&String.slice(&1, left(area, rect.width), rect.width))
  end

  defp cursor(screen, _area, _rect, _opts, false), do: screen

  defp cursor(screen, area, rect, opts, true) do
    x = rect.x + area.col - left(area, rect.width)
    y = rect.y + area.row - top(area, rect.height)

    if x in rect.x..(rect.x + rect.width - 1) and y in rect.y..(rect.y + rect.height - 1) do
      style = Keyword.get(opts, :cursor_style, Style.new(reverse: true))

      Screen.put(screen, x, y, under(area) || " ", style)
    else
      screen
    end
  end

  # The cursor sits on a character, not instead of one — including the first
  # one of the placeholder, which is all there is to sit on while it is empty.
  defp under(area) do
    case area |> line() |> graphemes() |> Enum.at(area.col) do
      nil -> if empty?(area), do: area.placeholder |> graphemes() |> Enum.at(area.col)
      grapheme -> grapheme
    end
  end

  defp top(area, height), do: area.row |> Kernel.-(height - 1) |> max(0)

  defp left(area, width), do: area.col |> Kernel.-(width - 1) |> max(0)

  ## Keys

  defp press(area, {:char, char}), do: {:ok, insert(area, char)}
  defp press(area, :enter), do: {:ok, split(area)}
  defp press(area, :backspace), do: {:ok, backspace(area)}
  defp press(area, :delete), do: {:ok, delete(area)}
  defp press(area, :left), do: {:ok, left(area)}
  defp press(area, :right), do: {:ok, right(area)}

  # At the top and the bottom the arrows belong to whoever holds the field.
  defp press(%{row: 0} = area, :up), do: {:pass, area}
  defp press(area, :up), do: {:ok, up(area)}
  defp press(area, :down), do: if(last?(area), do: {:pass, area}, else: {:ok, down(area)})

  defp press(area, key) when key in [:home, {[:ctrl], "a"}], do: {:ok, %{area | col: 0}}
  defp press(area, key) when key in [:end, {[:ctrl], "e"}], do: {:ok, %{area | col: len(area)}}
  defp press(area, {[:ctrl], "k"}), do: {:ok, kill_right(area)}
  defp press(area, {[:ctrl], "u"}), do: {:ok, kill_left(area)}
  defp press(area, _key), do: {:pass, area}

  defp insert(area, char) do
    {before, rest} = around(area)

    area |> put_line(before <> char <> rest) |> Map.put(:col, area.col + 1)
  end

  defp split(area) do
    {before, rest} = around(area)

    %{
      area
      | lines:
          List.replace_at(area.lines, area.row, before) |> List.insert_at(area.row + 1, rest),
        row: area.row + 1,
        col: 0
    }
  end

  defp backspace(%{row: 0, col: 0} = area), do: area

  defp backspace(%{col: 0} = area) do
    previous = Enum.at(area.lines, area.row - 1)
    {line, lines} = List.pop_at(area.lines, area.row)

    %{
      area
      | lines: List.replace_at(lines, area.row - 1, previous <> line),
        row: area.row - 1,
        col: length(graphemes(previous))
    }
  end

  defp backspace(area) do
    {before, rest} = around(area)

    area
    |> put_line(String.slice(before, 0, String.length(before) - 1) <> rest)
    |> Map.put(:col, area.col - 1)
  end

  defp delete(area) do
    cond do
      area.col < len(area) ->
        {before, rest} = around(area)

        put_line(area, before <> String.slice(rest, 1..-1//1))

      last?(area) ->
        area

      true ->
        {next, lines} = List.pop_at(area.lines, area.row + 1)

        %{area | lines: List.replace_at(lines, area.row, line(area) <> next)}
    end
  end

  defp left(%{row: 0, col: 0} = area), do: area
  defp left(%{col: 0} = area), do: %{area | row: area.row - 1, col: len(area, area.row - 1)}
  defp left(area), do: %{area | col: area.col - 1}

  defp right(area) do
    cond do
      area.col < len(area) -> %{area | col: area.col + 1}
      last?(area) -> area
      true -> %{area | row: area.row + 1, col: 0}
    end
  end

  defp up(area), do: %{area | row: area.row - 1, col: min(area.col, len(area, area.row - 1))}
  defp down(area), do: %{area | row: area.row + 1, col: min(area.col, len(area, area.row + 1))}

  defp kill_right(area) do
    {before, _rest} = around(area)

    put_line(area, before)
  end

  defp kill_left(area) do
    {_before, rest} = around(area)

    %{put_line(area, rest) | col: 0}
  end

  defp around(area) do
    line = line(area)

    {String.slice(line, 0, area.col), String.slice(line, area.col..-1//1) || ""}
  end

  defp put_line(area, text), do: %{area | lines: List.replace_at(area.lines, area.row, text)}

  defp line(area), do: Enum.at(area.lines, area.row, "")

  defp len(area), do: len(area, area.row)
  defp len(area, row), do: area.lines |> Enum.at(row, "") |> graphemes() |> length()

  defp last?(area), do: area.row >= length(area.lines) - 1

  defp graphemes(text), do: String.graphemes(text || "")
end
