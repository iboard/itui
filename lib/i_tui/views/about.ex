defmodule ITui.Views.About do
  @moduledoc """
  What this is, what it is built on, and where it came from.

  Opened with `?` from the menu and closed with `esc`, `q` or `enter`. Nothing
  in it is written down twice: the version and the description come from the
  application spec, and the toolkit and the runtime say their own versions, so
  the box cannot go stale.
  """

  use Atui.View

  alias Atui.{Layout, Style, Text}
  alias ITui.Views.Popup

  @home "github.com/iboard/itui"
  @license "GPL-3.0-or-later"
  @copyright "© 2026 Andreas Altendorfer"

  @impl Atui.View
  def mount(opts), do: {:ok, %{notify: Keyword.get(opts, :notify), width: 0}}

  @impl Atui.View
  def place(_state, viewport) do
    width = clamp(56, 32, viewport.width - 4)

    Rect.centered(viewport, width, clamp(length(lines(width - 4)) + 5, 9, viewport.height - 2))
  end

  @impl Atui.View
  def handle_key(key, state) when key in [:esc, :enter, {:char, "q"}], do: {:pop, state}
  def handle_key(_key, state), do: {:pass, state}

  @impl Atui.View
  def render(_state, rect) do
    {body, footer} = rect |> Rect.inset(1) |> Layout.split_bottom(1)
    # A column of air each side: a line that touches the border reads as a leak.
    lines = lines(body.width - 2)

    lines
    |> Enum.with_index(body.y + div(max(body.height - length(lines), 0), 2))
    |> Enum.reduce(blank(rect), fn {{text, style}, y}, screen ->
      Screen.put_text_centered(screen, body, y, text, style)
    end)
    |> Screen.put_text_centered(footer, footer.y, "esc close", dim())
  end

  @impl Atui.View
  def unmount(state), do: Popup.closed(state.notify, __MODULE__, :ok)

  defp blank(rect) do
    Screen.new(rect.width, rect.height)
    |> Screen.box(rect, title: " About ", chars: :round, style: Style.new(fg: :bright_black))
  end

  # The version and the description are what the application says about
  # itself; the toolkit and the runtime answer for their own.
  defp lines(width) do
    [{"iTUI #{ITui.version()}", Style.new(bold: true)}] ++
      Enum.map(Text.wrap(description(), width), &{&1, nil}) ++
      [
        {"", nil},
        {"ATUI #{Atui.version()} · Elixir #{System.version()} · OTP #{otp()}", dim()},
        {"", nil},
        {@home, Style.new(fg: :bright_cyan)},
        {@license, dim()},
        {"", nil},
        {@copyright, dim()}
      ]
  end

  defp description do
    case Application.spec(:i_tui, :description) do
      nil -> "A configurable terminal UI for Linux."
      description -> to_string(description)
    end
  end

  defp otp, do: :erlang.system_info(:otp_release) |> to_string()

  defp dim, do: Style.new(dim: true)

  defp clamp(value, low, high), do: value |> max(low) |> min(max(high, low))
end
