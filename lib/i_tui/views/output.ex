defmodule ITui.Views.Output do
  @moduledoc """
  A popup showing what a command printed.

  Pushed by `ITui.Views.MainMenu` once a command has finished, it owns the
  keyboard while it is open: arrows and `page up`/`page down` scroll, `esc`,
  `q` or `enter` close it. On the way out it tells whoever pushed it that it
  has gone — see `Atui.Popup` — so the menu knows the keys are its own
  again.
  """

  use Atui.View

  alias Atui.{Layout, Popup, Style, Text}

  @page 10

  @impl Atui.View
  def mount(opts) do
    {status, body} =
      case Keyword.fetch!(opts, :result) do
        {:ok, output} -> {:ok, output}
        {:error, message} -> {:error, message}
      end

    {:ok,
     %{
       title: Keyword.get(opts, :title, "Output"),
       subtitle: Keyword.get(opts, :subtitle),
       notify: Keyword.get(opts, :notify),
       status: status,
       lines: lines(body),
       scroll: 0
     }}
  end

  # Big enough for the output, small enough to leave the menu showing around it.
  @impl Atui.View
  def place(state, viewport) do
    width = state.lines |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)

    Rect.centered(
      viewport,
      clamp(width + 4, 32, viewport.width - 4),
      clamp(length(state.lines) + 4, 7, viewport.height - 2)
    )
  end

  @impl Atui.View
  def handle_key(key, state) when key in [:esc, :enter, {:char, "q"}], do: {:pop, state}

  def handle_key(key, state) when key in [:up, {:char, "k"}], do: {:ok, scroll(state, -1)}
  def handle_key(key, state) when key in [:down, {:char, "j"}], do: {:ok, scroll(state, 1)}
  def handle_key(:page_up, state), do: {:ok, scroll(state, -@page)}
  def handle_key(:page_down, state), do: {:ok, scroll(state, @page)}
  def handle_key(:home, state), do: {:ok, %{state | scroll: 0}}
  def handle_key(:end, state), do: {:ok, scroll(state, length(state.lines))}
  def handle_key(_key, state), do: {:pass, state}

  @impl Atui.View
  def render(state, rect) do
    {body, footer} = rect |> Rect.inset(1) |> Layout.split_bottom(1)
    {body, visible} = body_and_lines(state, body)

    Screen.new(rect.width, rect.height)
    |> Screen.box(rect, title: " #{state.title} ", style: border_style(state))
    |> subtitle(state, rect)
    |> put_lines(visible, body)
    |> Screen.put_text(footer.x + 1, footer.y, footer(state, visible, footer.width - 2), dim())
  end

  @impl Atui.View
  def unmount(state), do: Popup.closed(state.notify, __MODULE__, :ok)

  defp lines(body) do
    case body
         |> String.replace_suffix("\n", "")
         |> String.split("\n")
         |> Enum.map(&Text.sanitize/1) do
      [""] -> ["(no output)"]
      lines -> lines
    end
  end

  # The subtitle takes the first row of the body when there is one.
  defp body_and_lines(state, body) do
    body = if state.subtitle, do: elem(Layout.split_top(body, 2), 1), else: body

    {body, Enum.slice(state.lines, state.scroll, max(body.height, 0))}
  end

  defp subtitle(screen, %{subtitle: nil}, _rect), do: screen

  defp subtitle(screen, state, rect) do
    Screen.put_text(
      screen,
      rect.x + 2,
      rect.y + 1,
      Screen.truncate(state.subtitle, rect.width - 4),
      dim()
    )
  end

  # A line longer than the popup is cut rather than drawn over the border.
  defp put_lines(screen, lines, body) do
    lines
    |> Enum.with_index(body.y)
    |> Enum.reduce(screen, fn {line, y}, acc ->
      Screen.put_text(acc, body.x + 1, y, Screen.truncate(line, body.width - 2))
    end)
  end

  defp footer(state, visible, width) do
    first = state.scroll + 1
    last = state.scroll + length(visible)
    total = length(state.lines)

    Text.first_fitting(
      [
        "esc close · ↑↓ scroll · #{first}-#{last} of #{total}",
        "esc close · #{first}-#{last}/#{total}",
        "esc close"
      ],
      width
    )
  end

  defp border_style(%{status: :error}), do: Style.new(fg: :bright_red)
  defp border_style(_state), do: Style.new(fg: :bright_black)

  defp dim, do: Style.new(dim: true)

  # The last line can sit at the top of the body, and no further.
  defp scroll(state, by) do
    %{state | scroll: clamp(state.scroll + by, 0, length(state.lines) - 1)}
  end

  defp clamp(value, low, high), do: value |> max(low) |> min(max(high, low))
end
