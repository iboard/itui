defmodule ITui.Schema do
  @moduledoc """
  A data structure described in a file, and the casting of values into it.

  One declaration serves two purposes: it is what `ITui.Views.Form` draws a row
  for, and it is what `ITui.Repo` stores. A form collecting the parameters of a
  command and a todo list kept on disk are the same thing declared twice, so
  they are the same thing in the code as well.

      {
        "name": "todo",
        "label": "Todo",
        "title": "Todos",
        "source": "data/records/todos.json",
        "fields": [
          {"name": "title", "label": "Title", "type": "string", "required": true},
          {"name": "done", "label": "Done", "type": "boolean", "default": false}
        ]
      }

  `label` names one record and titles the form that edits it; `title` names the
  collection and heads the list of them, defaulting to `label`. `source` is
  where `ITui.Repo` keeps the records, and only matters for a schema that is
  stored; a form collecting the arguments of a command has no source at all.

  See `ITui.Schema.Field` for what a field may say about itself.
  """

  alias ITui.Schema.Field

  defstruct [:name, :label, :title, :source, fields: []]

  @type t :: %__MODULE__{
          name: String.t(),
          label: String.t(),
          title: String.t(),
          source: Path.t() | nil,
          fields: [Field.t()]
        }

  @doc """
  Reads a schema by name, or from an explicit path.

  A name is looked up as `schemas/<name>.json` under the data directory; a
  value ending in `.json` is taken as a path as it stands.
  """
  @spec load(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load(name_or_path) when is_binary(name_or_path) do
    path = path(name_or_path)

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
  Parses the contents of a schema file.

      iex> {:ok, schema} = ITui.Schema.parse(~s({"name": "note", "fields": [{"name": "body"}]}))
      iex> {schema.name, Enum.map(schema.fields, & &1.name)}
      {"note", ["body"]}

  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(contents) when is_binary(contents) do
    case Jason.decode(contents) do
      {:ok, decoded} -> from_map(decoded)
      {:error, error} -> {:error, "invalid JSON: #{Exception.message(error)}"}
    end
  end

  @doc """
  Builds a schema from a decoded JSON object.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(%{"fields" => fields} = map) when is_list(fields) do
    with {:ok, name} <- name(map),
         {:ok, fields} <- parse_fields(fields, name) do
      {:ok,
       %__MODULE__{
         name: name,
         label: label(map, name),
         title: title(map, label(map, name)),
         source: source(map, name),
         fields: fields
       }}
    end
  end

  def from_map(%{}), do: {:error, ~s(a schema needs a "fields" list)}
  def from_map(other), do: {:error, "expected a schema object, got: #{inspect(other)}"}

  @doc """
  Casts a form's parameters into the values the schema declares.

  Keys are the field names as strings; anything the schema does not declare is
  dropped, and anything it declares and the parameters do not mention falls
  back to the field's default. Every field is cast before the result is
  decided, so a form shows all of its mistakes at once rather than one per
  attempt.

      iex> {:ok, schema} = ITui.Schema.parse(~s({"name": "t", "fields": [{"name": "n", "type": "integer"}]}))
      iex> ITui.Schema.cast(schema, %{"n" => "12", "ignored" => "x"})
      {:ok, %{"n" => 12}}

      iex> {:ok, schema} = ITui.Schema.parse(~s({"name": "t", "fields": [{"name": "n", "type": "integer"}]}))
      iex> ITui.Schema.cast(schema, %{"n" => "x"})
      {:error, [{"n", "must be a whole number"}]}

  Naming the fields casts only those, which is what an update does:

      iex> json = ~s({"name": "t", "fields": [{"name": "a"}, {"name": "b"}]})
      iex> {:ok, schema} = ITui.Schema.parse(json)
      iex> ITui.Schema.cast(schema, %{"a" => "new"}, ["a"])
      {:ok, %{"a" => "new"}}

  """
  @spec cast(t(), map(), :all | [String.t()]) ::
          {:ok, map()} | {:error, [{String.t(), String.t()}]}
  def cast(schema, params, fields \\ :all)

  def cast(%__MODULE__{} = schema, params, fields) when is_map(params) do
    {values, errors} =
      schema
      |> fields(fields)
      |> Enum.reduce({%{}, []}, fn field, {values, errors} ->
        case Field.cast(field, Map.get(params, field.name)) do
          {:ok, value} -> {Map.put(values, field.name, value), errors}
          {:error, message} -> {values, [{field.name, message} | errors]}
        end
      end)

    case errors do
      [] -> {:ok, values}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  @doc """
  The fields to cast: every one of them, or the ones named.

  An update casts only what it was given, so setting one key does not reset
  the rest of the record to the defaults of the fields nobody mentioned.
  """
  @spec fields(t(), :all | [String.t()]) :: [Field.t()]
  def fields(%__MODULE__{fields: fields}, :all), do: fields

  def fields(%__MODULE__{fields: fields}, names) when is_list(names) do
    Enum.filter(fields, &(&1.name in names))
  end

  @doc """
  The field called `name`, or `nil`.
  """
  @spec field(t(), String.t()) :: Field.t() | nil
  def field(%__MODULE__{fields: fields}, name), do: Enum.find(fields, &(&1.name == name))

  @doc """
  Where the records of this schema are kept.
  """
  @spec source(t()) :: Path.t() | nil
  def source(%__MODULE__{source: source}), do: source

  defp path(name) do
    if String.ends_with?(name, ".json") do
      name
    else
      Path.join([data_dir(), "schemas", "#{name}.json"])
    end
  end

  defp name(%{"name" => name}) when is_binary(name) and name != "", do: {:ok, name}
  defp name(map), do: {:error, "a schema needs a name: #{inspect(Map.keys(map))}"}

  defp parse_fields(fields, name) do
    fields
    |> Enum.reduce_while({:ok, []}, fn map, {:ok, acc} ->
      case Field.from_map(map) do
        {:ok, field} -> {:cont, {:ok, [field | acc]}}
        {:error, reason} -> {:halt, {:error, ~s(in "#{name}": #{reason})}}
      end
    end)
    |> case do
      {:ok, fields} -> {:ok, Enum.reverse(fields)}
      error -> error
    end
  end

  defp label(%{"label" => label}, _name) when is_binary(label) and label != "", do: label
  defp label(_map, name), do: String.capitalize(name)

  defp title(%{"title" => title}, _label) when is_binary(title) and title != "", do: title
  defp title(_map, label), do: label

  defp source(%{"source" => source}, _name) when is_binary(source), do: source
  defp source(_map, _name), do: nil

  defp data_dir, do: Application.get_env(:i_tui, :data_dir, "data")
end
