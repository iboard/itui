defmodule ITui.Repo.Json do
  @moduledoc """
  Keeps a schema's records in the JSON file the schema names as its `source`,
  which is a path inside the data directory — see `ITui.Data`.

  The whole file is read, changed and written back on every call. For a todo
  list that is the right trade: the records stay a readable array of objects
  that anyone can open in an editor, and there is nothing to migrate, start or
  keep in sync. It is not a database — a second writer would overwrite the
  first — which is the line at which `ITui.Repo`'s other adapter takes over.

  A file that does not exist yet reads as an empty collection, so a schema
  works before anything has ever been stored.

  On the way in, the keys the schema declares become atoms and the rest are
  left as they are, so a key somebody added by hand survives being written
  back out.
  """

  @behaviour ITui.Repo

  alias ITui.Schema

  @impl ITui.Repo
  def all(%Schema{} = schema), do: read(schema)

  @impl ITui.Repo
  def get(%Schema{} = schema, id) do
    with {:ok, records} <- read(schema) do
      case find(records, id) do
        nil -> {:error, "no #{schema.name} with id #{id}"}
        record -> {:ok, record}
      end
    end
  end

  @impl ITui.Repo
  def insert(%Schema{} = schema, params) do
    with {:ok, values} <- Schema.cast(schema, params),
         {:ok, records} <- read(schema) do
      now = timestamp()
      record = Map.merge(values, %{id: next_id(records), inserted_at: now, updated_at: now})

      with :ok <- write(schema, records ++ [record]), do: {:ok, record}
    end
  end

  @impl ITui.Repo
  def update(%Schema{} = schema, id, params) do
    with {:ok, records} <- read(schema),
         {:ok, record} <- fetch(records, id, schema),
         # Only the keys that were given are cast, so setting one of them does
         # not disturb the fields nobody mentioned.
         {:ok, updated} <- Schema.change(schema, record, params, Map.keys(params)) do
      updated = Map.put(updated, :updated_at, timestamp())

      with :ok <- write(schema, replace(records, updated)), do: {:ok, updated}
    end
  end

  @impl ITui.Repo
  def delete(%Schema{} = schema, id) do
    with {:ok, records} <- read(schema),
         {:ok, record} <- fetch(records, id, schema) do
      write(schema, List.delete(records, record))
    end
  end

  defp read(%Schema{source: nil} = schema) do
    {:error, ~s(the "#{schema.name}" schema has no source to read records from)}
  end

  defp read(%Schema{source: source} = schema) do
    source = ITui.Data.path(source)

    case File.read(source) do
      {:ok, contents} -> decode(contents, schema)
      {:error, :enoent} -> {:ok, []}
      {:error, posix} -> {:error, "#{source}: #{:file.format_error(posix)}"}
    end
  end

  defp decode(contents, %Schema{source: source} = schema) do
    case Jason.decode(contents) do
      {:ok, records} when is_list(records) -> {:ok, Enum.map(records, &load(schema, &1))}
      {:ok, _other} -> {:error, "#{source}: expected a list of records"}
      {:error, error} -> {:error, "#{source}: invalid JSON: #{Exception.message(error)}"}
    end
  end

  defp write(%Schema{source: source}, records) do
    source = ITui.Data.path(source)
    contents = Jason.encode!(Enum.map(records, &dump/1), pretty: true) <> "\n"

    with :ok <- File.mkdir_p(Path.dirname(source)),
         :ok <- File.write(source, contents) do
      :ok
    else
      {:error, posix} -> {:error, "#{source}: #{:file.format_error(posix)}"}
    end
  end

  # The keys the schema knows about become atoms; anything else is left alone,
  # so a key somebody added by hand is still there when the file is rewritten.
  defp load(%Schema{} = schema, record) do
    keys =
      schema.fields
      |> Map.new(&{&1.name, &1.key})
      |> Map.merge(%{"id" => :id, "inserted_at" => :inserted_at, "updated_at" => :updated_at})

    Map.new(record, fn {key, value} -> {Map.get(keys, key, key), value} end)
  end

  defp dump(record), do: Map.new(record, fn {key, value} -> {to_string(key), value} end)

  defp fetch(records, id, schema) do
    case find(records, id) do
      nil -> {:error, "no #{schema.name} with id #{id}"}
      record -> {:ok, record}
    end
  end

  defp find(records, id), do: Enum.find(records, &(&1[:id] == id))

  defp replace(records, record) do
    Enum.map(records, fn existing ->
      if existing[:id] == record[:id], do: record, else: existing
    end)
  end

  defp next_id(records) do
    records
    |> Enum.map(&(&1[:id] || 0))
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
