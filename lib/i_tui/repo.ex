defmodule ITui.Repo do
  @moduledoc """
  Where records live, behind one small interface.

  The repository is a behaviour with an adapter behind it, so the views know
  how to ask for records without knowing what answers them.
  `ITui.Repo.Json` — the default — keeps each schema's records in the JSON file
  the schema names as its `source`, which is what makes the data as readable
  and as editable as the schemas themselves.

      config :i_tui, repo: ITui.Repo.Json

  Every function takes the `ITui.Schema` the records belong to: the schema says
  where they are kept and what they hold, so the adapter needs no configuration
  of its own per collection.

  ## Records

  A record is a plain map keyed by the field names as atoms — what
  `ITui.Schema` casts its parameters into. Three of the keys belong to the
  repository rather than to the schema: `:id`, `:inserted_at` and
  `:updated_at`.

  Parameters going the other way are keyed by the field names as strings, the
  way a form hands them over. Anything that will not cast comes back as
  `{:error, %Ecto.Changeset{}}`, which `ITui.Schema.errors/2` turns into
  something to show.
  """

  alias ITui.Schema

  @type id :: integer()
  @type record :: Schema.record()
  @type reason :: String.t() | Ecto.Changeset.t()

  @doc "Every record of the schema, oldest first."
  @callback all(Schema.t()) :: {:ok, [record()]} | {:error, reason()}

  @doc "The record with this id."
  @callback get(Schema.t(), id()) :: {:ok, record()} | {:error, reason()}

  @doc "Stores a new record, casting the parameters through the schema."
  @callback insert(Schema.t(), map()) :: {:ok, record()} | {:error, reason()}

  @doc "Casts and merges the given keys into the record with this id."
  @callback update(Schema.t(), id(), map()) :: {:ok, record()} | {:error, reason()}

  @doc "Removes the record with this id."
  @callback delete(Schema.t(), id()) :: :ok | {:error, reason()}

  @doc "The configured adapter."
  @spec adapter() :: module()
  def adapter, do: Application.get_env(:i_tui, :repo, ITui.Repo.Json)

  @doc "See `c:all/1`."
  @spec all(Schema.t()) :: {:ok, [record()]} | {:error, reason()}
  def all(schema), do: adapter().all(schema)

  @doc "See `c:get/2`."
  @spec get(Schema.t(), id()) :: {:ok, record()} | {:error, reason()}
  def get(schema, id), do: adapter().get(schema, id)

  @doc "See `c:insert/2`."
  @spec insert(Schema.t(), map()) :: {:ok, record()} | {:error, reason()}
  def insert(schema, params), do: adapter().insert(schema, params)

  @doc "See `c:update/3`."
  @spec update(Schema.t(), id(), map()) :: {:ok, record()} | {:error, reason()}
  def update(schema, id, params), do: adapter().update(schema, id, params)

  @doc "See `c:delete/2`."
  @spec delete(Schema.t(), id()) :: :ok | {:error, reason()}
  def delete(schema, id), do: adapter().delete(schema, id)
end
