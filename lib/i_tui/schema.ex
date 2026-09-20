defmodule ITui.Schema do
  @moduledoc """
  A data structure described in a file, cast and validated with Ecto.

  One declaration serves two purposes: it is what `ITui.Views.Form` draws a row
  for, and it is what `ITui.Repo` stores. A form collecting the parameters of a
  command and a todo list kept on disk are the same thing declared twice, so
  they are the same thing in the code as well.

      {
        "name": "todo",
        "label": "Todo",
        "title": "Todos",
        "source": "records/todos.json",
        "fields": [
          {"name": "title", "label": "Title", "type": "string", "required": true},
          {"name": "done", "label": "Done", "type": "boolean", "default": false}
        ]
      }

  `label` names one record and titles the form that edits it; `title` names the
  collection and heads the list of them, defaulting to `label`. `columns` says
  which fields the list gives a column to and in what order — a table reads in
  a different order from the form that fills it, and a field left out is shown
  beside the list instead — or `detail` says outright which fields are shown
  there, for a column worth repeating in full. `sort` names the column the list
  starts sorted by, and `stretch` the one that takes whatever width the other
  columns leave over. `source` is
  where `ITui.Repo` keeps the records — a path inside the data directory, see
  `ITui.Data` — and only matters for a schema that is stored; a form collecting the arguments of a command has no source at all.

  ## Ecto without a database

  The fields are only known when the file is read, so there is no module to
  `use Ecto.Schema` in — and no need for one. `Ecto.Changeset` takes a
  `{data, types}` pair as readily as it takes a struct, so `changeset/4` builds
  the types out of the fields and hands Ecto the same job it does anywhere
  else: cast the parameters, trim them, say what is missing, and apply the
  changes onto the record.

      iex> {:ok, schema} = ITui.Schema.load("todo")
      iex> changeset = ITui.Schema.changeset(schema, %{}, %{"title" => ""})
      iex> Enum.map(ITui.Schema.errors(schema, changeset), fn {f, m} -> {f.label, m} end)
      [{"Title", "is required"}]

  What comes out is a plain map keyed by the field names as atoms — the record
  `ITui.Repo` stores. There is no repository behind the changesets: `cast/3`
  and `change/4` end in `Ecto.Changeset.apply_action/2`, and the JSON file is
  the database.

  See `ITui.Schema.Field` for what a field may say about itself.
  """

  alias Ecto.Changeset
  alias ITui.Schema.Field

  defstruct [:name, :label, :title, :source, :sort, :columns, :detail, :stretch, fields: []]

  @type t :: %__MODULE__{
          name: String.t(),
          label: String.t(),
          title: String.t(),
          source: Path.t() | nil,
          sort: atom() | nil,
          columns: [atom()] | nil,
          detail: [atom()] | nil,
          stretch: atom() | nil,
          fields: [Field.t()]
        }

  @typedoc """
  A record as it is stored: the schema's fields, keyed by their names as atoms.

  Named `row` rather than `record` because Elixir keeps `record/0` for itself.
  """
  @type row :: %{atom() => term()}

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
         {:ok, fields} <- parse_fields(fields, name),
         {:ok, columns} <- name_list(map, "columns", fields, name),
         {:ok, detail} <- name_list(map, "detail", fields, name),
         {:ok, stretch} <- named(map, "stretch", fields, name),
         {:ok, sort} <- named(map, "sort", fields, name) do
      label = label(map, name)

      {:ok,
       %__MODULE__{
         name: name,
         label: label,
         title: title(map, label),
         source: source(map, name),
         sort: sort,
         columns: columns,
         detail: detail,
         stretch: stretch,
         fields: fields
       }}
    end
  end

  def from_map(%{}), do: {:error, ~s(a schema needs a "fields" list)}
  def from_map(other), do: {:error, "expected a schema object, got: #{inspect(other)}"}

  @doc """
  A changeset over `data`, casting the parameters the schema declares.

  Parameters are keyed by the field names as strings, the way a form hands them
  over; everything the schema does not declare is dropped. `fields` names what
  may change — `:all`, or the names of the fields an update was given, so
  setting one key does not disturb the rest of the record.

  An empty string clears the field it was typed into — emptying the text, or
  emptying a number altogether — and a required field refuses to be blank
  whatever its type.
  """
  @spec changeset(t(), row(), map(), :all | [String.t() | atom()]) :: Changeset.t()
  def changeset(%__MODULE__{} = schema, data, params, fields \\ :all) do
    casting = fields(schema, fields)
    {text, rest} = Enum.split_with(casting, &(&1.type == :string))

    {data, types(schema)}
    |> Changeset.cast(params, keys(rest), message: &message/2)
    |> Changeset.cast(params, keys(text), empty_values: [], message: &message/2)
    |> trim(text)
    |> validate_required(casting)
  end

  @doc """
  Casts parameters into a new record, starting from the schema's defaults.

      iex> {:ok, schema} = ITui.Schema.parse(~s({"name": "t", "fields": [{"name": "n", "type": "integer"}]}))
      iex> ITui.Schema.cast(schema, %{"n" => "12", "ignored" => "x"})
      {:ok, %{n: 12}}

  """
  @spec cast(t(), map(), :all | [String.t() | atom()]) ::
          {:ok, row()} | {:error, Changeset.t()}
  def cast(%__MODULE__{} = schema, params, fields \\ :all) do
    schema |> changeset(defaults(schema), params, fields) |> Changeset.apply_action(:insert)
  end

  @doc """
  Casts parameters onto a record that already exists.

  What comes back is the whole record with the changes applied, so a repository
  has nothing left to merge.
  """
  @spec change(t(), row(), map(), :all | [String.t() | atom()]) ::
          {:ok, row()} | {:error, Changeset.t()}
  def change(%__MODULE__{} = schema, record, params, fields \\ :all) do
    schema |> changeset(record, params, fields) |> Changeset.apply_action(:update)
  end

  @doc """
  What went wrong, as `{field, message}` in the order the fields are declared.

  A form shows them under the rows — and puts the cursor back on the first
  field that was wrong — so it gets the field itself rather than its name.
  """
  @spec errors(t(), Changeset.t()) :: [{Field.t(), String.t()}]
  def errors(%__MODULE__{} = schema, %Changeset{} = changeset) do
    messages = Changeset.traverse_errors(changeset, &interpolate/1)

    for field <- schema.fields,
        message <- Map.get(messages, field.key, []),
        do: {field, message}
  end

  @doc """
  The Ecto type of every field, which is what `Ecto.Changeset.cast/4` needs.

      iex> {:ok, schema} = ITui.Schema.parse(~s({"name": "t", "fields": [{"name": "n", "type": "integer"}]}))
      iex> ITui.Schema.types(schema)
      %{n: :integer}

  """
  @spec types(t()) :: %{atom() => Ecto.Type.t()}
  def types(%__MODULE__{fields: fields}), do: Map.new(fields, &{&1.key, &1.type})

  @doc """
  The record a new one starts from: every field at its default.
  """
  @spec defaults(t()) :: row()
  def defaults(%__MODULE__{fields: fields}), do: Map.new(fields, &{&1.key, Field.default(&1)})

  @doc """
  The fields to cast: every one of them, or the ones named.

  Names may be strings, as a form's parameters have them, or atoms.
  """
  @spec fields(t(), :all | [String.t() | atom()]) :: [Field.t()]
  def fields(%__MODULE__{fields: fields}, :all), do: fields

  def fields(%__MODULE__{fields: fields}, names) when is_list(names) do
    names = Enum.map(names, &to_string/1)

    Enum.filter(fields, &(&1.name in names))
  end

  @doc """
  The fields a form asks for — everything the schema does not keep to itself.
  """
  @spec form_fields(t()) :: [Field.t()]
  def form_fields(%__MODULE__{fields: fields}), do: Enum.filter(fields, & &1.form)

  @doc """
  The fields a list gives a column to, in the order it draws them.

  That is `columns` when the schema names them — a table reads in a different
  order from the form that fills it — and every field otherwise.
  """
  @spec list_fields(t()) :: [Field.t()]
  def list_fields(%__MODULE__{columns: nil, fields: fields}), do: fields

  def list_fields(%__MODULE__{columns: columns} = schema) do
    Enum.map(columns, &field(schema, &1))
  end

  @doc """
  The fields a list shows beside itself, for the row the cursor is on.

  That is `detail` when the schema names them — a column too narrow to read is
  worth repeating in full down there — and otherwise the fields `columns`
  leaves out, which is where a description or a link belongs.
  """
  @spec detail_fields(t()) :: [Field.t()]
  def detail_fields(%__MODULE__{detail: detail} = schema) when is_list(detail) do
    Enum.map(detail, &field(schema, &1))
  end

  def detail_fields(%__MODULE__{columns: nil}), do: []

  def detail_fields(%__MODULE__{columns: columns, fields: fields}) do
    Enum.reject(fields, &(&1.key in columns))
  end

  @doc """
  The field called `name`, or `nil`. The name may be a string or an atom.
  """
  @spec field(t(), String.t() | atom()) :: Field.t() | nil
  def field(%__MODULE__{fields: fields}, name) do
    name = to_string(name)

    Enum.find(fields, &(&1.name == name))
  end

  @doc """
  Where the records of this schema are kept.
  """
  @spec source(t()) :: Path.t() | nil
  def source(%__MODULE__{source: source}), do: source

  # Ecto trims only to decide whether a value is empty; a form has its own
  # reasons to want the spaces gone.
  defp trim(changeset, fields) do
    fields
    |> Enum.filter(&(&1.type == :string))
    |> Enum.reduce(changeset, fn field, acc ->
      Changeset.update_change(acc, field.key, fn
        value when is_binary(value) -> String.trim(value)
        value -> value
      end)
    end)
  end

  # An empty string means two different things, so it is cast twice. For a
  # number or a yes/no it is nothing, and clearing the field empties it; for
  # text it is a value, and clearing the field stores that. For a field that
  # is required it is nothing again, whatever its type — which is what a
  # person filling in a form means by leaving it blank.
  defp validate_required(changeset, fields) do
    required = fields |> Enum.filter(& &1.required) |> keys()

    %{changeset | empty_values: [""]}
    |> Changeset.validate_required(required, message: "is required")
  end

  defp keys(fields), do: Enum.map(fields, & &1.key)

  defp message(_key, metadata), do: Field.invalid_message(Keyword.get(metadata, :type))

  defp interpolate({message, opts}) do
    Regex.replace(~r/%\{(\w+)\}/, message, fn _whole, key ->
      opts |> Keyword.get(String.to_existing_atom(key), "") |> to_string()
    end)
  end

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

  # `columns` and `detail` each name a list of fields, in the order they are
  # drawn: the table's columns, and what is shown beside the list.
  defp name_list(map, key, fields, name) do
    case Map.get(map, key) do
      nil ->
        {:ok, nil}

      names when is_list(names) ->
        gather(names, key, fields, name)

      names ->
        {:error,
         ~s(the #{key} of "#{name}" must be a list of field names, got: ) <> inspect(names)}
    end
  end

  defp gather(names, key, fields, name) do
    names
    |> Enum.reduce_while({:ok, []}, fn named, {:ok, acc} ->
      case Enum.find(fields, &(&1.name == named)) do
        nil ->
          {:halt,
           {:error,
            ~s(the #{key} of "#{name}" name something that is not a field: ) <> inspect(named)}}

        field ->
          {:cont, {:ok, [field.key | acc]}}
      end
    end)
    |> case do
      {:ok, keys} -> {:ok, Enum.reverse(keys)}
      error -> error
    end
  end

  # `sort` and `stretch` each name one field: the column a list starts sorted
  # by, and the one that takes whatever width the others leave over.
  defp named(map, key, fields, name) do
    case Map.get(map, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        case Enum.find(fields, &(&1.name == value)) do
          nil -> {:error, ~s(the #{key} of "#{name}" is not one of its fields: #{inspect(value)})}
          field -> {:ok, field.key}
        end

      value ->
        {:error, ~s(the #{key} of "#{name}" must be a field name, got: #{inspect(value)})}
    end
  end

  defp data_dir, do: Application.get_env(:i_tui, :data_dir, "data")
end
