defmodule ITui.Menu.Item do
  @moduledoc """
  One entry of a menu: a submenu, a command to run, an application to open, or
  a built-in action.

  An item is parsed from one JSON object and carries exactly one of the four.
  Which one it is decides what pressing Enter on it does, and `type/1` names it:

      iex> {:ok, item} = ITui.Menu.Item.from_map(%{"label" => "Uptime", "command" => "uptime"})
      iex> ITui.Menu.Item.type(item)
      :command

  ## The shape of an item

      {
        "key": "d",                    // optional: the character that selects it
        "label": "Disk free",          // required
        "description": "Free space",   // optional, shown under the list
        "command": "df",               // a command entry ...
        "args": ["-h"]                 //   ... and its arguments
      }

  A submenu carries `"items"` instead of `"command"`, an application carries
  `"view"` (see `ITui.Views` for the names), and a built-in carries `"action"`
  — `"quit"` is the only one so far.

  A command entry may also name a `"form"`: the schema whose fields are asked
  for before it runs, and whose values fill the `{{placeholders}}` in its
  arguments.

      {
        "key": "p",
        "label": "Ping a host",
        "command": "ping",
        "args": ["-c", "{{count}}", "{{host}}"],
        "form": "ping"
      }
  """

  alias ITui.Command

  defstruct [:key, :label, :description, :command, :items, :action, :view, :form]

  @type t :: %__MODULE__{
          key: String.t() | nil,
          label: String.t(),
          description: String.t() | nil,
          command: Command.t() | nil,
          items: [t()] | nil,
          action: atom() | nil,
          view: String.t() | nil,
          form: String.t() | nil
        }

  @actions %{"quit" => :quit}

  @doc """
  Parses one decoded JSON object into an item.

  Returns `{:error, message}` for anything an item cannot be: a missing label,
  a multi-character key, an unknown action, or an entry that says both what
  command to run and what submenu to open.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(%{} = map) do
    with {:ok, label} <- label(map),
         {:ok, key} <- key(map, label),
         {:ok, form} <- form(map, label),
         {:ok, target} <- target(map, label) do
      {:ok,
       struct!(
         %__MODULE__{
           key: key,
           label: label,
           description: string(map["description"]),
           form: form
         },
         target
       )}
    end
  end

  def from_map(other), do: {:error, "expected a menu item object, got: #{inspect(other)}"}

  @doc """
  What kind of entry this is: `:submenu`, `:command`, `:view` or `:action`.
  """
  @spec type(t()) :: :submenu | :command | :view | :action
  def type(%__MODULE__{items: items}) when is_list(items), do: :submenu
  def type(%__MODULE__{command: %Command{}}), do: :command
  def type(%__MODULE__{view: view}) when is_binary(view), do: :view
  def type(%__MODULE__{action: action}) when is_atom(action) and not is_nil(action), do: :action

  @doc """
  A one-line summary of what the entry does, for the column beside the label.

  A command shows itself; a submenu says it has more behind it.

      iex> {:ok, item} = ITui.Menu.Item.from_map(%{"label" => "Disk free", "command" => "df", "args" => ["-h"]})
      iex> ITui.Menu.Item.hint(item)
      "df -h"

  """
  @spec hint(t()) :: String.t()
  def hint(%__MODULE__{} = item) do
    case type(item) do
      :command -> Command.to_string(item.command)
      :submenu -> "#{length(item.items)} #{entries(length(item.items))} →"
      :view -> "opens #{item.view}"
      :action -> "#{item.action}"
    end
  end

  defp entries(1), do: "entry"
  defp entries(_count), do: "entries"

  defp label(%{"label" => label}) when is_binary(label) and label != "", do: {:ok, label}
  defp label(map), do: {:error, "a menu item needs a label: #{inspect(map)}"}

  defp key(%{"key" => key}, label) when is_binary(key) do
    if String.length(key) == 1,
      do: {:ok, key},
      else: {:error, ~s(the key of "#{label}" must be a single character, got: #{inspect(key)})}
  end

  defp key(%{"key" => key}, label) when not is_nil(key) do
    {:error, ~s(the key of "#{label}" must be a string, got: #{inspect(key)})}
  end

  defp key(_map, _label), do: {:ok, nil}

  # Exactly one of the three: an item that both runs and descends has no
  # sensible answer to Enter, so it is a broken menu file rather than a guess.
  defp target(map, label) do
    case Enum.filter(["items", "command", "view", "action"], &is_map_key(map, &1)) do
      ["items"] -> submenu(map["items"], label)
      ["command"] -> command(map, label)
      ["view"] -> view(map["view"], label)
      ["action"] -> action(map["action"], label)
      [] -> {:error, ~s("#{label}" does nothing: it needs items, a command, a view or an action)}
      many -> {:error, ~s("#{label}" has more than one of #{Enum.join(many, ", ")})}
    end
  end

  defp submenu(items, label) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn map, {:ok, acc} ->
      case from_map(map) do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        {:error, reason} -> {:halt, {:error, ~s(in "#{label}": #{reason})}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, [items: Enum.reverse(items)]}
      error -> error
    end
  end

  defp submenu(other, label) do
    {:error, ~s(the items of "#{label}" must be a list, got: #{inspect(other)})}
  end

  defp command(%{"command" => program} = map, label) when is_binary(program) do
    case args(map["args"], label) do
      {:ok, args} -> {:ok, [command: Command.new(program, args)]}
      error -> error
    end
  end

  defp command(map, label) do
    {:error, ~s(the command of "#{label}" must be a string, got: #{inspect(map["command"])})}
  end

  defp args(nil, _label), do: {:ok, []}

  defp args(args, label) when is_list(args) do
    if Enum.all?(args, &is_binary/1),
      do: {:ok, args},
      else: {:error, ~s(every argument of "#{label}" must be a string: #{inspect(args)})}
  end

  defp args(other, label) do
    {:error, ~s(the args of "#{label}" must be a list, got: #{inspect(other)})}
  end

  defp view(view, _label) when is_binary(view) and view != "", do: {:ok, [view: view]}

  defp view(other, label) do
    {:error, ~s(the view of "#{label}" must be a name, got: #{inspect(other)})}
  end

  defp form(%{"form" => form}, _label) when is_binary(form) and form != "", do: {:ok, form}

  defp form(%{"form" => form}, label) when not is_nil(form) do
    {:error, ~s(the form of "#{label}" must be a schema name, got: #{inspect(form)})}
  end

  defp form(_map, _label), do: {:ok, nil}

  defp action(action, label) when is_binary(action) do
    case Map.fetch(@actions, action) do
      {:ok, known} ->
        {:ok, [action: known]}

      :error ->
        known = @actions |> Map.keys() |> Enum.sort() |> Enum.join(", ")
        {:error, ~s(unknown action #{inspect(action)} in "#{label}"; known actions: #{known})}
    end
  end

  defp action(other, label) do
    {:error, ~s(the action of "#{label}" must be a string, got: #{inspect(other)})}
  end

  defp string(value) when is_binary(value), do: value
  defp string(_value), do: nil
end
