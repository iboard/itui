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
        "short": "T",             // optional: what a column calls it
        "type": "string",         // string (default), integer, boolean, date, datetime
        "required": true,         // optional
        "default": "",            // optional: the value before anything is typed
        "placeholder": "what to do",
        "form": false,            // optional: never asked for
        "lines": 4                // optional: a field of several lines
      }

  `lines` above one makes the form draw an `Atui.TextArea` instead of a
  single-line field, and `short` is for a label too wide to head a column.

  `form` is what a field says about where it belongs: a timestamp the
  application writes itself is `"form": false`, because there is nothing to
  ask. Which fields are columns, and in what order, is the schema's business
  rather than the field's — see `ITui.Schema`.
  """

  alias ITui.Schema.{Boolean, Timestamp}

  defstruct [
    :name,
    :key,
    :label,
    :short,
    :default,
    :placeholder,
    type: :string,
    required: false,
    form: true,
    lines: 1
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          key: atom(),
          label: String.t(),
          short: String.t() | nil,
          type: Ecto.Type.t(),
          required: boolean(),
          default: term(),
          placeholder: String.t() | nil,
          form: boolean(),
          lines: pos_integer()
        }

  @types %{
    "string" => :string,
    "integer" => :integer,
    "boolean" => Boolean,
    "date" => ITui.Schema.Date,
    "datetime" => Timestamp
  }

  @doc """
  Parses one decoded JSON object into a field.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(%{} = map) do
    with {:ok, name} <- name(map),
         {:ok, type} <- type(map, name) do
      with {:ok, lines} <- lines(map, name) do
        field = %__MODULE__{
          name: name,
          # Field names come from the application's own schema files, a list as
          # bounded as the files themselves — not from anything a user types.
          key: String.to_atom(name),
          label: label(map, name),
          short: string(map["short"]),
          type: type,
          required: map["required"] == true,
          placeholder: placeholder(map),
          form: map["form"] != false,
          lines: lines
        }

        default(field, map)
      end
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
  What a column calls the field: its `short` label, or its label.

      iex> {:ok, field} = ITui.Schema.Field.from_map(%{"name" => "priority", "short" => "P"})
      iex> {ITui.Schema.Field.short(field), field.label}
      {"P", "Priority"}

  """
  @spec short(t()) :: String.t()
  def short(%__MODULE__{short: nil, label: label}), do: label
  def short(%__MODULE__{short: short}), do: short

  @doc """
  True for a field the form gives more than one line to.
  """
  @spec multiline?(t()) :: boolean()
  def multiline?(%__MODULE__{lines: lines}), do: lines > 1

  @doc """
  The message a form shows when a value will not cast.

      iex> {:ok, field} = ITui.Schema.Field.from_map(%{"name" => "n", "type" => "integer"})
      iex> ITui.Schema.Field.invalid_message(field.type)
      "must be a whole number"

  """
  @spec invalid_message(Ecto.Type.t()) :: String.t() | nil
  def invalid_message(:integer), do: "must be a whole number"
  def invalid_message(Boolean), do: "must be yes or no"
  def invalid_message(Timestamp), do: "must be a date and time"
  def invalid_message(ITui.Schema.Date), do: "must be a date, as 2026-09-25 or in 3 days"
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
  def format(%__MODULE__{type: Timestamp}, value), do: Timestamp.format(value)
  def format(%__MODULE__{type: ITui.Schema.Date}, value), do: ITui.Schema.Date.format(value)
  def format(%__MODULE__{}, nil), do: ""
  def format(%__MODULE__{}, value), do: to_string(value)

  @doc """
  The value as a column shows it when it is showing dates as they stand from
  today: `+3 days` for a date or a timestamp, and the plain value for the rest.

      iex> {:ok, field} = ITui.Schema.Field.from_map(%{"name" => "due", "type" => "date"})
      iex> ITui.Schema.Field.relative(field, "2026-09-21", ~D[2026-09-19])
      "+2 days"

  """
  @spec relative(t(), term(), Date.t()) :: String.t()
  def relative(%__MODULE__{type: ITui.Schema.Date}, value, today) do
    value |> ITui.Schema.Date.parse() |> ITui.Schema.Date.relative(today)
  end

  def relative(%__MODULE__{type: Timestamp}, value, today) do
    value |> Timestamp.to_date() |> ITui.Schema.Date.relative(today)
  end

  def relative(%__MODULE__{} = field, value, _today), do: format(field, value)

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

  defp lines(%{"lines" => lines}, _name) when is_integer(lines) and lines > 0, do: {:ok, lines}

  defp lines(%{"lines" => lines}, name) when not is_nil(lines) do
    {:error, ~s(the lines of "#{name}" must be a whole number above zero, got: #{inspect(lines)})}
  end

  defp lines(_map, _name), do: {:ok, 1}

  defp string(value) when is_binary(value) and value != "", do: value
  defp string(_value), do: nil
end
