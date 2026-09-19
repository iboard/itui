defmodule ITui.Views.Filter do
  @moduledoc """
  A popup for choosing which kinds of todo the list shows.

  The kinds are the colours the list already draws — done, overdue, due this
  week, and the rest — so what is being hidden is named the way the screen
  already says it. Each carries how many there are of it, because hiding a
  band of nothing is worth knowing before you go looking for what moved.

  It is pushed by `ITui.Views.Todo`, and every change goes straight back to it
  — the list behind the popup is filtered as the boxes are ticked, not when
  the popup closes, because seeing what a filter does is most of choosing it.
  The set of kinds to hide goes back again on the way out (see
  `ITui.Views.Popup`).

  ## Keys

    * `↑`/`↓` or `k`/`j` — move
    * `space` — show this kind, or hide it
    * `a` — show all of them again
    * `esc` or `enter` — done
  """

  use Atui.View

  alias Atui.{Layout, Style, Text}
  alias ITui.Views.Popup

  @impl Atui.View
  def mount(opts) do
    {:ok,
     %{
       bands: Keyword.fetch!(opts, :bands),
       counts: Keyword.get(opts, :counts, %{}),
       hidden: Keyword.get(opts, :hidden, MapSet.new()),
       notify: Keyword.get(opts, :notify),
       cursor: 0
     }}
  end

  @impl Atui.View
  def place(state, viewport) do
    Rect.centered(
      viewport,
      clamp(width(state) + 14, 34, viewport.width - 4),
      clamp(length(state.bands) + 4, 7, viewport.height - 2)
    )
  end

  @impl Atui.View
  def handle_key(key, state) when key in [:esc, :enter], do: {:pop, state}
  def handle_key(key, state) when key in [:up, {:char, "k"}], do: {:ok, move(state, -1)}
  def handle_key(key, state) when key in [:down, {:char, "j"}], do: {:ok, move(state, 1)}
  def handle_key({:char, " "}, state), do: {:ok, announce(toggle(state))}
  def handle_key({:char, "a"}, state), do: {:ok, announce(%{state | hidden: MapSet.new()})}
  def handle_key(_key, state), do: {:pass, state}

  @impl Atui.View
  def render(state, rect) do
    {body, footer} = rect |> Rect.inset(1) |> Layout.split_bottom(1)

    state.bands
    |> Enum.with_index()
    |> Enum.reduce(blank(rect), fn {band, index}, screen ->
      row(screen, state, band, %{body | y: body.y + index, height: 1}, index == state.cursor)
    end)
    |> Screen.put_text(footer.x + 1, footer.y, keys(footer.width - 2), dim())
  end

  @impl Atui.View
  def unmount(state), do: Popup.closed(state.notify, __MODULE__, {:hidden, state.hidden})

  defp blank(rect) do
    Screen.new(rect.width, rect.height)
    |> Screen.box(rect, title: " Show ", chars: :round, style: Style.new(fg: :bright_black))
  end

  defp row(screen, state, {tone, label}, rect, selected?) do
    style = if selected?, do: Style.new(fg: :black, bg: :bright_cyan)
    box = if MapSet.member?(state.hidden, tone), do: "[ ] ", else: "[x] "
    count = state.counts |> Map.get(tone, 0) |> Integer.to_string()

    screen
    |> Screen.fill(rect, " ", style)
    |> Screen.put_text(rect.x + 1, rect.y, box <> label, style || tone_style(state, tone))
    |> Screen.put_text_right(rect, rect.y, count, style || dim(), 1)
  end

  # A kind nobody is showing is not worth the ink of its own name.
  defp tone_style(state, tone) do
    if MapSet.member?(state.hidden, tone), do: dim()
  end

  defp keys(width) do
    Text.first_fitting(
      [
        "space show or hide · a all · esc done",
        "space show/hide · a all · esc done",
        "space show/hide · esc",
        "space · a · esc"
      ],
      width
    )
  end

  defp announce(state) do
    Popup.tell(state.notify, {:filter_changed, state.hidden})

    state
  end

  defp toggle(state) do
    case Enum.at(state.bands, state.cursor) do
      nil ->
        state

      {tone, _label} ->
        hidden =
          if MapSet.member?(state.hidden, tone),
            do: MapSet.delete(state.hidden, tone),
            else: MapSet.put(state.hidden, tone)

        %{state | hidden: hidden}
    end
  end

  defp move(state, by) do
    case length(state.bands) do
      0 -> state
      count -> %{state | cursor: Integer.mod(state.cursor + by, count)}
    end
  end

  defp width(state) do
    state.bands
    |> Enum.map(fn {_tone, label} -> String.length(label) end)
    |> Enum.max(fn -> 0 end)
  end

  defp dim, do: Style.new(dim: true)

  defp clamp(value, low, high), do: value |> max(low) |> min(max(high, low))
end
