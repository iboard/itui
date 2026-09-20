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

  ## Opening somewhere in particular

  The command line can say where to go before anyone has pressed anything —
  `itui menu system/uptime`, `itui todo` — and it says so in the options this
  view is mounted with:

    * `:open` — a path of names through the menu (see `ITui.Menu.resolve/2`),
      walked down to the entry it names and then activated, exactly as though
      enter had been pressed on it
    * `:open_view` — the name of an application to open straight away
      (see `ITui.Views`), whether or not the menu has an entry for it

  A view may only push another view from a callback, never from `mount/1`, so
  the instruction is posted as this view's own first event and carried out as
  soon as the runtime is listening.

  ## Keys

    * `↑`/`↓` or `k`/`j` — move
    * `enter` or `→` — open a submenu, or run a command
    * an entry's own key — the same, without moving first
    * `esc`, `←` or `backspace` — back out of a submenu
    * `?` — what this is, and what it is built on
    * `q` — quit
  """

  use Atui.View

  alias Atui.{Layout, Style, Text}
  alias ITui.{Command, Menu, Schema, Views}
  alias ITui.Menu.Item
  alias ITui.Views.{About, Form, Output}

  @impl Atui.View
  def mount(opts) do
    {menu, error} =
      case Keyword.fetch(opts, :menu) do
        {:ok, %Menu{} = menu} -> {menu, nil}
        :error -> load(Keyword.get(opts, :path))
      end

    opening(Keyword.get(opts, :open, []), Keyword.get(opts, :open_view))

    {:ok,
     %{
       menu: menu,
       trail: [],
       cursor: 0,
       error: error,
       busy: nil,
       pending: nil,
       popup?: false
     }}
  end

  @impl Atui.View
  def handle_key(:ctrl_c, state), do: {:halt, state}

  # The popup owns the keyboard while it is open. The flag is set when the
  # popup is pushed and cleared when it says it has closed (`Atui.Popup`),
  # so a key that
  # arrives in the same read as the one that closed it is dropped rather than
  # moving a cursor nobody can see — the safer of the two mistakes.
  def handle_key(_key, %{popup?: true} = state), do: {:pass, state}

  def handle_key({:char, "q"}, state), do: {:halt, state}

  def handle_key({:char, "?"}, state) do
    {:push, About, [notify: __MODULE__], %{state | popup?: true}}
  end

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
  def handle_event({:output, result}, %{busy: {%Item{} = item, command}} = state) do
    {:push, Output,
     [
       title: item.label,
       subtitle: Command.to_string(command),
       result: result,
       notify: __MODULE__
     ], %{state | busy: nil, popup?: true}}
  end

  # What the command line asked for, now that there is a runtime to ask.
  def handle_event({:open, segments}, state) do
    case Menu.resolve(state.menu.items, segments) do
      {:ok, chain} -> jump(state, chain)
      {:error, reason} -> complain(state, Enum.join(segments, "/"), reason)
    end
  end

  def handle_event({:open_view, name}, state) do
    open(state, %Item{label: name, view: name})
  end

  # The form the entry asked for has closed with values: now the command runs.
  def handle_event({:popup_closed, Form, {:submitted, attrs}}, %{pending: %Item{} = item} = state) do
    {:ok, run(%{state | pending: nil, popup?: false}, item, attrs)}
  end

  def handle_event({:popup_closed, _module, _result}, state) do
    {:ok, %{state | popup?: false, pending: nil}}
  end

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

  defp status(%{busy: {%Item{}, command}}, width) do
    Screen.truncate("running #{Command.to_string(command)} …", width)
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
    Text.first_fitting(
      [
        "↑↓ move · enter run · ? about · q quit",
        "↑↓ move · enter run · q quit",
        "↑↓ · enter · q"
      ],
      width
    )
  end

  defp keys(_state, width) do
    Text.first_fitting(
      [
        "↑↓ move · enter run · esc back · ? about · q quit",
        "↑↓ move · enter run · esc back · q quit",
        "↑↓ · enter · esc · q"
      ],
      width
    )
  end

  defp activate(state, nil), do: {:ok, state}

  defp activate(state, %Item{} = item) do
    case Item.type(item) do
      :submenu -> {:ok, descend(state, item)}
      :action -> action(state, item.action)
      :view -> open(state, item)
      :command -> command(state, item)
    end
  end

  defp action(state, :quit), do: {:halt, state}

  # An entry that names a form asks for its arguments before it runs anything.
  defp command(state, %Item{form: nil} = item), do: {:ok, run(state, item, %{})}

  defp command(state, %Item{form: name} = item) do
    case Schema.load(name) do
      {:ok, schema} ->
        {:push, Form, [schema: schema, title: item.label, notify: __MODULE__],
         %{state | pending: item, popup?: true}}

      {:error, reason} ->
        complain(state, item.label, reason)
    end
  end

  defp open(state, %Item{view: name} = item) do
    case Views.fetch(name) do
      {:ok, module} -> {:push, module, [notify: __MODULE__], %{state | popup?: true}}
      {:error, reason} -> complain(state, item.label, reason)
    end
  end

  # A menu file that names something that is not there is worth saying out
  # loud, rather than a key that quietly does nothing.
  defp complain(state, title, reason) do
    {:push, Output, [title: title, result: {:error, reason}, notify: __MODULE__],
     %{state | popup?: true}}
  end

  # A view may not push anything from mount/1, and the runtime is this process
  # while a view is mounting — so an instruction from the command line is
  # posted to this view and arrives as its first event.
  defp opening([], nil), do: :ok
  defp opening(_segments, name) when is_binary(name), do: tell({:open_view, name})
  defp opening(segments, _name) when is_list(segments), do: tell({:open, segments})

  defp tell(event), do: Atui.Runtime.send_event_to(self(), __MODULE__, event)

  # Down to the entry the path names, and then whatever enter would have done
  # to it — which may be to descend once more, to run something, or to quit.
  defp jump(state, chain) do
    {above, [last]} = Enum.split(chain, -1)
    state = Enum.reduce(above, state, fn item, acc -> acc |> select(item) |> descend(item) end)

    activate(select(state, last), last)
  end

  # Off the runtime's process: a slow command must not stop the UI drawing.
  defp run(state, %Item{} = item, params) do
    command = Command.render(item.command, params)

    Atui.Fetch.start(__MODULE__, :output, fn -> Command.run(command) end)

    %{state | busy: {item, command}}
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
