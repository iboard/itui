defmodule ITui.Schema.Field do
  @moduledoc """
  One field of a schema: what it is called, what it holds, and how to read it.

  A field is what a form draws a row for and what a record keeps a key for, so
  the same declaration serves both. `cast/2` turns whatever a form collected —
  always text, or a toggle's `true`/`false` — into the value the field is
  declared to hold, or says why it cannot.

      iex> {:ok, field} = ITui.Schema.Field.from_map(%{"name" => "count", "type" => "integer"})
      iex> ITui.Schema.Field.cast(field, "3")
      {:ok, 3}

      iex> {:ok, field} = ITui.Schema.Field.from_map(%{"name" => "count", "type" => "integer"})
      iex> ITui.Schema.Field.cast(field, "three")
      {:error, "must be a whole number"}

  ## The shape of a field

      {
        "name": "title",          // required: the key in the record
        "label": "Title",         // optional: what the form calls it
        "type": "string",         // string (default), integer or boolean
        "required": true,         // optional
        "default": "",            // optional: used when the key is absent
        "placeholder": "what to do"
      }
  """

  defstruct [:name, :label, :default, :placeholder, type: :string, required: false]

  @type type :: :string | :integer | :boolean

  @type t :: %__MODULE__{
          name: String.t(),
          label: String.t(),
          type: type(),
          required: boolean(),
          default: term(),
          placeholder: String.t() | nil
        }

  @types %{"string" => :string, "integer" => :integer, "boolean" => :boolean}

  @truthy ~w(true yes y 1 on)
  @falsy ~w(false no n 0 off)

  @doc """
  Parses one decoded JSON object into a field.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(%{} = map) do
    with {:ok, name} <- name(map),
         {:ok, type} <- type(map, name) do
      field = %__MODULE__{
        name: name,
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
  Casts one value to the field's type.

  `nil` means the key was absent, which is where a default applies; a field
  that is required and has neither is an error. Values that are already of the
  right type pass straight through, so a toggle's `true` needs no round trip
  through "yes".
  """
  @spec cast(t(), term()) :: {:ok, term()} | {:error, String.t()}
  def cast(%__MODULE__{default: default} = field, nil) when not is_nil(default) do
    cast(field, default)
  end

  def cast(%__MODULE__{required: true}, nil), do: {:error, "is required"}
  def cast(%__MODULE__{type: :boolean}, nil), do: {:ok, false}
  def cast(%__MODULE__{}, nil), do: {:ok, nil}

  def cast(%__MODULE__{type: :string} = field, value) do
    case value |> to_string() |> String.trim() do
      "" -> if field.required, do: {:error, "is required"}, else: {:ok, ""}
      trimmed -> {:ok, trimmed}
    end
  end

  def cast(%__MODULE__{type: :integer}, value) when is_integer(value), do: {:ok, value}

  def cast(%__MODULE__{type: :integer} = field, value) do
    case value |> to_string() |> String.trim() do
      "" ->
        if field.required, do: {:error, "is required"}, else: {:ok, nil}

      trimmed ->
        case Integer.parse(trimmed) do
          {number, ""} -> {:ok, number}
          _otherwise -> {:error, "must be a whole number"}
        end
    end
  end

  def cast(%__MODULE__{type: :boolean}, value) when is_boolean(value), do: {:ok, value}

  def cast(%__MODULE__{type: :boolean}, value) do
    case value |> to_string() |> String.trim() |> String.downcase() do
      truthy when truthy in @truthy -> {:ok, true}
      falsy when falsy in @falsy -> {:ok, false}
      "" -> {:ok, false}
      _otherwise -> {:error, "must be yes or no"}
    end
  end

  @doc """
  The value as a form or a list would show it.

      iex> {:ok, field} = ITui.Schema.Field.from_map(%{"name" => "done", "type" => "boolean"})
      iex> ITui.Schema.Field.format(field, true)
      "yes"

  """
  @spec format(t(), term()) :: String.t()
  def format(%__MODULE__{type: :boolean}, true), do: "yes"
  def format(%__MODULE__{type: :boolean}, _value), do: "no"
  def format(%__MODULE__{}, nil), do: ""
  def format(%__MODULE__{}, value), do: to_string(value)

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

  # A default is declared in the file the way a value is written, so it goes
  # through the same cast as anything typed into the form.
  defp default(field, map) do
    case Map.fetch(map, "default") do
      :error ->
        {:ok, field}

      {:ok, value} ->
        case cast(%{field | required: false, default: nil}, value) do
          {:ok, default} -> {:ok, %{field | default: default}}
          {:error, message} -> {:error, ~s(the default of "#{field.name}" #{message})}
        end
    end
  end

  defp label(%{"label" => label}, _name) when is_binary(label) and label != "", do: label
  defp label(_map, name), do: name |> String.replace("_", " ") |> String.capitalize()

  defp placeholder(%{"placeholder" => text}) when is_binary(text), do: text
  defp placeholder(_map), do: nil
end
