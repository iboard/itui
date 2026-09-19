defmodule ITui.Schema.Field do
  @moduledoc """
  One field of a schema: what it is called, what it holds, and how to read it.

  A field is what a form draws a row for and what a record keeps a key for, so
  the same declaration serves both. The type is an `Ecto.Type` — `:string`,
  `:integer` or `ITui.Schema.Boolean` — and `ITui.Schema` builds an
  `Ecto.Changeset` out of a schema's fields to cast whatever a form collected.

      iex> {:ok, field} = ITui.Schema.Field.from_map(%{"name" => "count", "type" => "integer"})
      iex> {field.key, field.type}
      {:count, :integer}

  ## The shape of a field

      {
        "name": "title",          // required: the key in the record
        "label": "Title",         // optional: what the form calls it
        "type": "string",         // string (default), integer or boolean
        "required": true,         // optional
        "default": "",            // optional: the value before anything is typed
        "placeholder": "what to do"
      }
  """

  alias ITui.Schema.Boolean

  defstruct [:name, :key, :label, :default, :placeholder, type: :string, required: false]

  @type t :: %__MODULE__{
          name: String.t(),
          key: atom(),
          label: String.t(),
          type: Ecto.Type.t(),
          required: boolean(),
          default: term(),
          placeholder: String.t() | nil
        }

  @types %{"string" => :string, "integer" => :integer, "boolean" => Boolean}

  @doc """
  Parses one decoded JSON object into a field.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(%{} = map) do
    with {:ok, name} <- name(map),
         {:ok, type} <- type(map, name) do
      field = %__MODULE__{
        name: name,
        # Field names come from the application's own schema files, a list as
        # bounded as the files themselves — not from anything a user types.
        key: String.to_atom(name),
        label: label(map, name),
        type: type,
        required: map["required"] == true,
        placeholder: placeholder(map)
      }

      default(field, map)
    end
  end

  def from_map(other), do: {:error, "expected a field object, got: #{inspect(other)}"}

  @doc """
  Casts one value to the field's type, the way `Ecto.Type.cast/2` does.

      iex> {:ok, field} = ITui.Schema.Field.from_map(%{"name" => "n", "type" => "integer"})
      iex> {ITui.Schema.Field.cast(field, "3"), ITui.Schema.Field.cast(field, "three")}
      {{:ok, 3}, :error}

  """
  @spec cast(t(), term()) :: {:ok, term()} | :error
  def cast(%__MODULE__{type: type}, value), do: Ecto.Type.cast(type, value)

  @doc """
  The message a form shows when a value will not cast.

      iex> {:ok, field} = ITui.Schema.Field.from_map(%{"name" => "n", "type" => "integer"})
      iex> ITui.Schema.Field.invalid_message(field.type)
      "must be a whole number"

  """
  @spec invalid_message(Ecto.Type.t()) :: String.t() | nil
  def invalid_message(:integer), do: "must be a whole number"
  def invalid_message(Boolean), do: "must be yes or no"
  def invalid_message(_type), do: nil

  @doc """
  The value as a form or a list would show it.

      iex> {:ok, field} = ITui.Schema.Field.from_map(%{"name" => "done", "type" => "boolean"})
      iex> ITui.Schema.Field.format(field, true)
      "yes"

  """
  @spec format(t(), term()) :: String.t()
  def format(%__MODULE__{type: Boolean}, true), do: "yes"
  def format(%__MODULE__{type: Boolean}, _value), do: "no"
  def format(%__MODULE__{}, nil), do: ""
  def format(%__MODULE__{}, value), do: to_string(value)

  @doc """
  The value a field starts at when nothing has been stored: its default, or
  nothing at all — except a yes/no field, which is always one or the other.
  """
  @spec default(t()) :: term()
  def default(%__MODULE__{type: Boolean, default: nil}), do: false
  def default(%__MODULE__{default: default}), do: default

  defp name(%{"name" => name}) when is_binary(name) and name != "", do: {:ok, name}
  defp name(map), do: {:error, "a field needs a name: #{inspect(map)}"}

  defp type(%{"type" => type}, name) when is_binary(type) do
    case Map.fetch(@types, type) do
      {:ok, known} ->
        {:ok, known}

      :error ->
        known = @types |> Map.keys() |> Enum.sort() |> Enum.join(", ")
        {:error, ~s(unknown type #{inspect(type)} for "#{name}"; known types: #{known})}
    end
  end

  defp type(%{"type" => type}, name) when not is_nil(type) do
    {:error, ~s(the type of "#{name}" must be a string, got: #{inspect(type)})}
  end

  defp type(_map, _name), do: {:ok, :string}

  # A default is written in the file the way a value is written, so it goes
  # through the same cast as anything typed into the form.
  defp default(field, map) do
    case Map.fetch(map, "default") do
      :error ->
        {:ok, field}

      {:ok, value} ->
        case cast(field, value) do
          {:ok, default} ->
            {:ok, %{field | default: default}}

          :error ->
            message = invalid_message(field.type) || "is not a #{inspect(field.type)}"
            {:error, ~s(the default of "#{field.name}" #{message})}
        end
    end
  end

  defp label(%{"label" => label}, _name) when is_binary(label) and label != "", do: label
  defp label(_map, name), do: name |> String.replace("_", " ") |> String.capitalize()

  defp placeholder(%{"placeholder" => text}) when is_binary(text), do: text
  defp placeholder(_map), do: nil
end
