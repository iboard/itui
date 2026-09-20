defmodule ITui.Menu do
  @moduledoc """
  A menu, read from a JSON file.

  The menu is data, not code: `data/menus/main.json` describes the entries, and
  `load/1` turns it into a tree of `ITui.Menu.Item` structs for a view to draw.
  A menu file that does not make sense is reported as `{:error, message}` and
  shown in the UI — the application still starts, because a terminal saying
  what is wrong with the file is more use than one that refuses to open.

      {
        "title": "iTUI",
        "items": [
          {"key": "u", "label": "Uptime", "command": "uptime"}
        ]
      }

  See `ITui.Menu.Item` for the shape of an entry.
  """

  alias ITui.Menu.Item

  defstruct title: "iTUI", items: []

  @type t :: %__MODULE__{title: String.t(), items: [Item.t()]}

  @doc """
  Reads and parses a menu file.

  Defaults to `default_path/0`. Returns `{:error, message}` if the file cannot
  be read, is not JSON, or is not a menu.
  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, String.t()}
  def load(path \\ nil) do
    path = path || default_path()

    case File.read(path) do
      {:ok, contents} ->
        with {:error, reason} <- parse(contents) do
          {:error, "#{path}: #{reason}"}
        end

      {:error, posix} ->
        {:error, "#{path}: #{:file.format_error(posix)}"}
    end
  end

  @doc """
  Parses the contents of a menu file.

      iex> {:ok, menu} = ITui.Menu.parse(~s({"title": "Demo", "items": [{"label": "Up", "command": "uptime"}]}))
      iex> {menu.title, length(menu.items)}
      {"Demo", 1}

  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(contents) when is_binary(contents) do
    case Jason.decode(contents) do
      {:ok, decoded} -> from_map(decoded)
      {:error, error} -> {:error, "invalid JSON: #{Exception.message(error)}"}
    end
  end

  @doc """
  Builds a menu from a decoded JSON object.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(%{"items" => items} = map) when is_list(items) do
    # A menu is an unnamed item with children, so the item parser does the work
    # and the same error messages come out of both.
    case Item.from_map(%{"label" => title(map), "items" => items}) do
      {:ok, item} -> {:ok, %__MODULE__{title: item.label, items: item.items}}
      error -> error
    end
  end

  def from_map(%{}), do: {:error, ~s(a menu needs an "items" list)}
  def from_map(other), do: {:error, "expected a menu object, got: #{inspect(other)}"}

  @doc """
  Where the menu file lives.

  `config :i_tui, :menu_file` overrides it outright; otherwise it is
  `menus/main.json` under `config :i_tui, :data_dir` (`"data"` by default),
  resolved against the working directory.
  """
  @spec default_path() :: Path.t()
  def default_path do
    Application.get_env(:i_tui, :menu_file) ||
      Path.join([Application.get_env(:i_tui, :data_dir, "data"), "menus", "main.json"])
  end

  @doc """
  The item in `items` selected by `key`, or `nil`.

      iex> {:ok, menu} = ITui.Menu.parse(~s({"items": [{"key": "u", "label": "Up", "command": "uptime"}]}))
      iex> ITui.Menu.find_by_key(menu.items, "u").label
      "Up"

  """
  @spec find_by_key([Item.t()], String.t()) :: Item.t() | nil
  def find_by_key(items, key) when is_list(items) and is_binary(key) do
    Enum.find(items, &(&1.key == key))
  end

  @doc """
  Walks a path of names into the menu: the entries it names, outermost first.

  This is how the command line says where to go — `itui menu system/uptime` —
  so a segment is written the way a person would write it rather than the way
  the file does. It is matched against an entry's key first, then against its
  label, ignoring case and punctuation, and then against the beginning of a
  label as long as only one entry starts that way.

      iex> {:ok, menu} = ITui.Menu.parse(~s({"items": [{"key": "s", "label": "System", "items": [{"label": "Disk free", "command": "df"}]}]}))
      iex> {:ok, chain} = ITui.Menu.resolve(menu.items, ["s", "disk-free"])
      iex> Enum.map(chain, & &1.label)
      ["System", "Disk free"]

  Returns `{:error, message}` for a name that matches nothing, a name that
  matches more than one entry, and a path that goes on past an entry with
  nothing inside it.
  """
  @spec resolve([Item.t()], [String.t()]) :: {:ok, [Item.t()]} | {:error, String.t()}
  def resolve(items, segments) when is_list(items) and is_list(segments) do
    segments
    |> Enum.reduce_while({:ok, {items, []}}, fn segment, {:ok, {level, chain}} ->
      case step(level, segment, chain) do
        {:ok, item} -> {:cont, {:ok, {item.items || [], [item | chain]}}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, {_level, chain}} -> {:ok, Enum.reverse(chain)}
      error -> error
    end
  end

  defp step([], segment, chain) do
    {:error, ~s(#{where(chain)} has nothing in it, so there is no "#{segment}" in it)}
  end

  defp step(items, segment, chain) do
    case find(items, segment) do
      {:ok, item} ->
        {:ok, item}

      {:error, :none} ->
        {:error, ~s(there is no "#{segment}" in #{where(chain)}; there is: #{labels(items)})}

      {:error, {:many, found}} ->
        {:error, ~s("#{segment}" could be any of: #{labels(found)})}
    end
  end

  @doc """
  The entry of `items` that `name` names: its key, its label, or the beginning
  of its label.

  `{:error, :none}` when nothing matches and `{:error, {:many, items}}` when a
  beginning matches more than one, which is a question rather than an answer.
  """
  @spec find([Item.t()], String.t()) :: {:ok, Item.t()} | {:error, :none | {:many, [Item.t()]}}
  def find(items, name) when is_list(items) and is_binary(name) do
    wanted = normalise(name)

    with nil <- find_by_key(items, name),
         nil <- Enum.find(items, &(normalise(&1.label) == wanted)) do
      case Enum.filter(items, &String.starts_with?(normalise(&1.label), wanted)) do
        [item] -> {:ok, item}
        [] -> {:error, :none}
        many -> {:error, {:many, many}}
      end
    else
      %Item{} = item -> {:ok, item}
    end
  end

  # A name is written the way it is said: "disk-free", "Disk free", "DISK FREE".
  defp normalise(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp where([]), do: "the menu"
  defp where([%Item{label: label} | _rest]), do: ~s("#{label}")

  defp labels(items), do: Enum.map_join(items, ", ", & &1.label)

  defp title(%{"title" => title}) when is_binary(title) and title != "", do: title
  defp title(_map), do: "iTUI"
end
