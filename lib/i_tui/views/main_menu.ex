defmodule ITui.Views.MainMenu do
  @moduledoc """
  The root view: the menu itself.

  It draws the entries of the current level, moves a cursor through them, and
  descends into submenus. Enter — or an entry's own key — runs the command
  behind it through `Atui.Fetch`, so the UI keeps drawing and stays quittable
  while `df` is off doing its work; the output arrives as an event and opens an
  `ITui.Views.Output` popup.

  Being the root view, it sees every key before the focused one does. While a
  popup is open it therefore passes everything but Ctrl-C along, so the arrows
  scroll the output instead of quietly moving a cursor nobody can see.

  ## Keys

    * `↑`/`↓` or `k`/`j` — move
    * `enter` or `→` — open a submenu, or run a command
    * an entry's own key — the same, without moving first
    * `esc`, `←` or `backspace` — back out of a submenu
    * `q` — quit
  """

  use Atui.View

  alias Atui.{Layout, Style, Text}
  alias ITui.{Command, Menu}
  alias ITui.Menu.Item

  @impl Atui.View
  def mount(opts) do
    {menu, error} =
      case Keyword.fetch(opts, :menu) do
        {:ok, %Menu{} = menu} -> {menu, nil}
        :error -> load(Keyword.get(opts, :path))
      end

    {:ok, %{menu: menu, trail: [], cursor: 0, error: error, busy: nil, popup?: false}}
  end

  @impl Atui.View
  def handle_key(:ctrl_c, state), do: {:halt, state}

  # The popup owns the keyboard while it is open. The flag is set when the
  # popup is pushed and cleared when it says it has closed, so a key that
  # arrives in the same read as the one that closed it is dropped rather than
  # moving a cursor nobody can see — the safer of the two mistakes.
  def handle_key(_key, %{popup?: true} = state), do: {:pass, state}

  def handle_key({:char, "q"}, state), do: {:halt, state}

  # A command is running: the only thing left to do is wait, or leave.
  def handle_key(_key, %{busy: busy} = state) when not is_nil(busy), do: {:ok, state}

  def handle_key(key, state) when key in [:up, {:char, "k"}], do: {:ok, move(state, -1)}
  def handle_key(key, state) when key in [:down, {:char, "j"}], do: {:ok, move(state, 1)}
  def handle_key(:home, state), do: {:ok, %{state | cursor: 0}}
  def handle_key(:end, state), do: {:ok, %{state | cursor: max(length(items(state)) - 1, 0)}}

  def handle_key(key, state) when key in [:enter, :right, {:char, "l"}] do
    activate(state, current_item(state))
  end

  def handle_key(key, state) when key in [:esc, :backspace, :left, {:char, "h"}] do
    {:ok, ascend(state)}
  end

  def handle_key({:char, char}, state) do
    case Menu.find_by_key(items(state), char) do
      nil -> {:pass, state}
      item -> activate(select(state, item), item)
    end
  end

  def handle_key(_key, state), do: {:pass, state}

  @impl Atui.View
  def handle_event({:output, result}, %{busy: %Item{} = item} = state) do
    {:push, ITui.Views.Output,
     [
       title: item.label,
       subtitle: Command.to_string(item.command),
       result: result,
       notify: __MODULE__
     ], %{state | busy: nil, popup?: true}}
  end

  def handle_event(:output_closed, state), do: {:ok, %{state | popup?: false}}
  def handle_event(_event, state), do: {:ok, state}

  @impl Atui.View
  def render(state, rect) do
    {header, rest} = rect |> Rect.inset(1) |> Layout.split_top(2)
    {list, footer} = Layout.split_bottom(rest, 2)

    Screen.new(rect.width, rect.height)
    |> Screen.box(rect, title: " #{state.menu.title} #{ITui.version()} ", style: border())
    |> Screen.put_text(header.x + 1, header.y, breadcrumb(state), Style.new(bold: true))
    |> body(state, list)
    |> Screen.put_text(footer.x + 1, footer.y, status(state, footer.width - 2), dim())
    |> Screen.put_text(footer.x + 1, footer.y + 1, keys(state, footer.width - 2), dim())
  end

  defp load(path) do
    case Menu.load(path) do
      {:ok, menu} -> {menu, nil}
      {:error, reason} -> {%Menu{}, reason}
    end
  end

  defp body(screen, %{error: error}, rect) when is_binary(error) do
    error
    |> Text.wrap(max(rect.width - 2, 1))
    |> Enum.with_index(rect.y)
    |> Enum.reduce(screen, fn {line, y}, acc ->
      Screen.put_text(acc, rect.x + 1, y, line, Style.new(fg: :bright_red))
    end)
  end

  defp body(screen, state, rect) do
    state
    |> items()
    |> Enum.with_index()
    |> Enum.reduce(screen, fn {item, index}, acc ->
      row(acc, item, Rect.new(rect.x, rect.y + index, rect.width, 1), index == state.cursor)
    end)
  end

  defp row(screen, _item, %Rect{y: y}, _selected) when y < 0, do: screen

  defp row(screen, item, rect, selected?) do
    style = if selected?, do: Style.new(fg: :black, bg: :bright_cyan), else: nil
    marker = if selected?, do: "▸ ", else: "  "
    key = if item.key, do: "#{item.key}  ", else: "   "

    screen
    |> Screen.fill(rect, " ", style)
    |> Screen.put_text(rect.x + 1, rect.y, marker <> key <> item.label, style)
    |> Screen.put_text_right(rect, rect.y, Item.hint(item), style || dim(), 2)
  end

  defp breadcrumb(%{menu: menu, trail: trail}) do
    [menu.title | Enum.map(trail, fn {item, _cursor} -> item.label end)]
    |> Enum.join(" › ")
  end

  defp status(%{error: error}, _width) when is_binary(error), do: "the menu could not be loaded"

  defp status(%{busy: %Item{} = item}, width) do
    Screen.truncate("running #{Command.to_string(item.command)} …", width)
  end

  defp status(state, width) do
    case current_item(state) do
      %Item{description: description} when is_binary(description) ->
        Screen.truncate(description, width)

      _none ->
        ""
    end
  end

  defp keys(%{trail: []}, width) do
    Text.first_fitting(["↑↓ move · enter run · q quit", "↑↓ · enter · q"], width)
  end

  defp keys(_state, width) do
    Text.first_fitting(["↑↓ move · enter run · esc back · q quit", "↑↓ · enter · esc · q"], width)
  end

  defp activate(state, nil), do: {:ok, state}

  defp activate(state, %Item{} = item) do
    case Item.type(item) do
      :submenu -> {:ok, descend(state, item)}
      :action -> action(state, item.action)
      :command -> {:ok, run(state, item)}
    end
  end

  defp action(state, :quit), do: {:halt, state}

  # Off the runtime's process: a slow command must not stop the UI drawing.
  defp run(state, %Item{} = item) do
    Atui.Fetch.start(__MODULE__, :output, fn -> Command.run(item.command) end)

    %{state | busy: item}
  end

  defp descend(state, %Item{} = item) do
    %{state | trail: state.trail ++ [{item, state.cursor}], cursor: 0}
  end

  defp ascend(%{trail: []} = state), do: state

  defp ascend(state) do
    {{_item, cursor}, trail} = List.pop_at(state.trail, -1)

    %{state | trail: trail, cursor: cursor}
  end

  # Pressing an entry's own key moves the cursor there as well, so the screen
  # agrees with what is about to happen.
  defp select(state, %Item{} = item) do
    %{state | cursor: Enum.find_index(items(state), &(&1 == item)) || state.cursor}
  end

  defp items(%{menu: menu, trail: []}), do: menu.items
  defp items(%{trail: trail}), do: trail |> List.last() |> elem(0) |> Map.fetch!(:items)

  defp current_item(state), do: state |> items() |> Enum.at(state.cursor)

  defp move(state, by) do
    case length(items(state)) do
      0 -> state
      count -> %{state | cursor: Integer.mod(state.cursor + by, count)}
    end
  end

  defp border, do: Style.new(fg: :bright_black)
  defp dim, do: Style.new(dim: true)
end
