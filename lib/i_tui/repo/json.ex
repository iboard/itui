defmodule ITui.Repo.Json do
  @moduledoc """
  Keeps a schema's records in the JSON file the schema names as its `source`.

  The whole file is read, changed and written back on every call. For a todo
  list that is the right trade: the records stay a readable array of objects
  that anyone can open in an editor, and there is nothing to migrate, start or
  keep in sync. It is not a database — a second writer would overwrite the
  first — which is the line at which `ITui.Repo`'s other adapter takes over.

  A file that does not exist yet reads as an empty collection, so a schema
  works before anything has ever been stored.
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

      record =
        values
        |> Map.put("id", next_id(records))
        |> Map.put("inserted_at", now)
        |> Map.put("updated_at", now)

      with :ok <- write(schema, records ++ [record]), do: {:ok, record}
    end
  end

  @impl ITui.Repo
  def update(%Schema{} = schema, id, params) do
    # Only the keys that were given are cast, so setting one of them does not
    # reset the rest of the record to the defaults of the fields not mentioned.
    with {:ok, values} <- Schema.cast(schema, params, Map.keys(params)),
         {:ok, records} <- read(schema),
         {:ok, record} <- fetch(records, id, schema) do
      updated = record |> Map.merge(values) |> Map.put("updated_at", timestamp())

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

  defp read(%Schema{source: source}) do
    case File.read(source) do
      {:ok, contents} -> decode(contents, source)
      {:error, :enoent} -> {:ok, []}
      {:error, posix} -> {:error, "#{source}: #{:file.format_error(posix)}"}
    end
  end

  defp decode(contents, source) do
    case Jason.decode(contents) do
      {:ok, records} when is_list(records) -> {:ok, records}
      {:ok, _other} -> {:error, "#{source}: expected a list of records"}
      {:error, error} -> {:error, "#{source}: invalid JSON: #{Exception.message(error)}"}
    end
  end

  defp write(%Schema{source: source}, records) do
    with :ok <- File.mkdir_p(Path.dirname(source)),
         :ok <- File.write(source, Jason.encode!(records, pretty: true) <> "\n") do
      :ok
    else
      {:error, posix} -> {:error, "#{source}: #{:file.format_error(posix)}"}
    end
  end

  defp fetch(records, id, schema) do
    case find(records, id) do
      nil -> {:error, "no #{schema.name} with id #{id}"}
      record -> {:ok, record}
    end
  end

  defp find(records, id), do: Enum.find(records, &(&1["id"] == id))

  defp replace(records, record) do
    Enum.map(records, fn existing ->
      if existing["id"] == record["id"], do: record, else: existing
    end)
  end

  defp next_id(records) do
    records
    |> Enum.map(&(&1["id"] || 0))
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
