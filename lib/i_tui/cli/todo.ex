defmodule ITui.CLI.Todo do
  @moduledoc """
  The todo list without a screen: adding one, checking one off, and printing
  the list.

  Everything it knows about a todo comes from the schema, exactly as
  `ITui.Views.Todo` does: the options `add/2` takes are the fields the schema
  asks a form for, the columns `list/2` prints are the columns the schema
  names, and the kinds `list/2` filters by are `ITui.Band`'s — the same words
  the filter on the screen uses. A field added to `schemas/todo.json` is an
  option here without a line of code changing.

      itui todo add "Buy milk" --due tomorrow --priority 1
      itui todo done 3
      itui todo list --hide done

  Each function does the work and returns what to say about it, so the only
  thing left for `ITui.CLI` to do is print it and choose an exit status.
  """

  alias ITui.{Band, Repo, Schema}
  alias ITui.Schema.{Boolean, Field, Timestamp}

  @type answer :: {:say, String.t()} | {:error, String.t()}

  # A column of a table is read across, not down: what does not fit in this
  # much of it is not worth the width it would cost the rest.
  @max_column 40
  @gap 2

  @doc """
  Adds a todo from the options given, and says what was stored.

  Every field the schema asks a form for is an option — `--title`, `--due`,
  `--priority` — and a yes/no field is the option on its own, `--done`. The
  words left over fill the field a todo is named by, which is the first one
  the form asks for that is text and must be there:

      itui todo add "Buy milk" --due tomorrow

  Values are cast by the schema, so what comes back for a date that is not one
  is what the form would have said about it.
  """
  @spec add(Schema.t(), [String.t()]) :: answer()
  def add(schema, argv) do
    with {:ok, params} <- params(schema, argv),
         {:ok, record} <- insert(schema, params) do
      {:say, "added #{line(schema, record)}"}
    end
  end

  @doc """
  Checks off the todos with these numbers — the `#` column of the list.

  A todo that was already ticked is left as it was and said so; the moment the
  tick went in is written to the schema's `done_at` field, the same as the
  screen does it.
  """
  @spec check(Schema.t(), [String.t()]) :: answer()
  def check(_schema, []) do
    {:error, "itui todo done takes the number of a todo: itui todo done 3"}
  end

  def check(schema, numbers) do
    # Every number is looked up before any of them is written, so a typo at
    # the end of the line does not leave half the work done and unsaid.
    with :ok <- checkable(schema),
         {:ok, ids} <- ids(numbers),
         {:ok, records} <- each(Enum.uniq(ids), &fetch(schema, &1)),
         {:ok, said} <- each(records, &check_one(schema, &1)) do
      {:say, Enum.join(said, "\n")}
    end
  end

  @doc """
  Prints the todos as a table, in the columns and the order the schema names.

  `--only` and `--hide` take the kinds of todo `ITui.Band` names, as a list
  separated by commas or as the option again:

      itui todo list --hide done
      itui todo list --only overdue,soon

  """
  @spec list(Schema.t(), [String.t()]) :: answer()
  def list(schema, argv) do
    with {:ok, only, hidden} <- filters(argv),
         {:ok, records} <- all(schema) do
      today = ITui.Schema.Date.local_today()

      records
      |> Enum.filter(&shown?(schema, &1, today, only, hidden))
      |> sorted(schema)
      |> table(schema)
    end
  end

  ## Adding

  defp params(schema, argv) do
    fields = Schema.form_fields(schema)

    case OptionParser.parse(argv, strict: switches(fields)) do
      {parsed, words, []} ->
        parsed
        |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
        |> named(schema, words)

      {_parsed, _words, [{option, _value} | _rest]} ->
        {:error,
         ~s(there is no #{option} on a #{String.downcase(schema.label)}; ) <> takes(fields)}
    end
  end

  defp switches(fields), do: Enum.map(fields, &{&1.key, switch_type(&1)})

  # Everything but a yes/no arrives as text and is cast by the schema, so a
  # value it will not take is refused in the schema's own words.
  defp switch_type(%Field{type: Boolean}), do: :boolean
  defp switch_type(%Field{}), do: :string

  defp takes(fields) do
    "it takes: " <> Enum.map_join(fields, ", ", &"--#{option(&1)}")
  end

  defp option(%Field{name: name}), do: String.replace(name, "_", "-")

  defp named(params, _schema, []), do: {:ok, params}

  defp named(params, schema, words) do
    said = Enum.join(words, " ")

    case naming_field(schema) do
      nil ->
        {:error, ~s(I do not know where to put "#{said}"; #{takes(Schema.form_fields(schema))})}

      field ->
        if Map.has_key?(params, field.name),
          do: {:error, ~s(--#{option(field)} was given as well as "#{said}")},
          else: {:ok, Map.put(params, field.name, said)}
    end
  end

  # What a todo is called: the first field the form asks for that is text and
  # must be there. It is the one the words left over fill, and the one a
  # record is named by when there is something to say about it.
  defp naming_field(schema) do
    fields = Schema.form_fields(schema)

    Enum.find(fields, &(&1.type == :string and &1.required)) ||
      Enum.find(fields, &(&1.type == :string))
  end

  defp insert(schema, params) do
    with {:error, reason} <- Repo.insert(schema, params), do: {:error, message(schema, reason)}
  end

  ## Checking off

  defp checkable(schema) do
    case Schema.field(schema, :done) do
      %Field{type: Boolean} -> :ok
      _other -> {:error, ~s(the "#{schema.name}" schema has no yes/no "done" field to tick)}
    end
  end

  defp ids(numbers) do
    each(numbers, fn number ->
      case Integer.parse(number) do
        {id, ""} -> {:ok, id}
        _not_a_number -> {:error, ~s("#{number}" is not the number of a todo)}
      end
    end)
  end

  defp fetch(schema, id) do
    with {:error, reason} <- Repo.get(schema, id), do: {:error, message(schema, reason)}
  end

  defp check_one(schema, record) do
    if Band.done?(record) do
      {:ok, "#{line(schema, record)} was already done"}
    else
      case Repo.update(schema, record[:id], checked(schema)) do
        {:ok, record} -> {:ok, "checked off #{line(schema, record)}"}
        {:error, reason} -> {:error, message(schema, reason)}
      end
    end
  end

  # "Checked off" is the moment the tick went in, so it is written with it.
  defp checked(schema) do
    if Schema.field(schema, :done_at),
      do: %{"done" => true, "done_at" => Timestamp.now()},
      else: %{"done" => true}
  end

  ## Listing

  defp filters(argv) do
    case OptionParser.parse(argv, strict: [only: [:string, :keep], hide: [:string, :keep]]) do
      {parsed, [], []} ->
        with {:ok, only} <- bands(parsed, :only),
             {:ok, hidden} <- bands(parsed, :hide) do
          {:ok, only, hidden}
        end

      {_parsed, [word | _rest], []} ->
        {:error, ~s(itui todo list takes no words, only --only and --hide: "#{word}")}

      {_parsed, _words, [{option, _value} | _rest]} ->
        {:error, "there is no #{option} on itui todo list; it takes --only and --hide"}
    end
  end

  # Said as a list or said again: --only done,overdue and --only done --only
  # overdue are the same thing, because both are how a person would write it.
  defp bands(parsed, key) do
    parsed
    |> Keyword.get_values(key)
    |> Enum.flat_map(&String.split(&1, ",", trim: true))
    |> each(&Band.fetch(String.trim(&1)))
  end

  # Nothing said about what to show shows everything; --hide takes from that.
  defp shown?(schema, record, today, only, hidden) do
    band = Band.of(schema, record, today)

    (only == [] or band in only) and band not in hidden
  end

  defp all(schema) do
    with {:error, reason} <- Repo.all(schema), do: {:error, message(schema, reason)}
  end

  # The order the list opens in, so the two agree about what is first.
  defp sorted(records, %Schema{sort: nil}), do: records

  defp sorted(records, %Schema{sort: key}) do
    Enum.sort_by(records, &{is_nil(&1[key]), &1[key]})
  end

  defp table(records, schema) do
    case Schema.list_fields(schema) do
      [] -> {:say, "the \"#{schema.name}\" schema has no columns to print"}
      _fields when records == [] -> {:say, "no #{String.downcase(schema.title)} to show"}
      fields -> {:say, rows(fields, records)}
    end
  end

  defp rows(fields, records) do
    widths = Enum.map(fields, &width(&1, records))
    heading = row(fields, widths, fn field -> Field.short(field) end)
    rule = widths |> Enum.map_join(String.duplicate(" ", @gap), &String.duplicate("─", &1))

    lines = Enum.map(records, fn record -> row(fields, widths, &cell(&1, record)) end)

    Enum.join([heading, rule | lines], "\n")
  end

  defp row(fields, widths, value) do
    fields
    |> Enum.zip(widths)
    |> Enum.map_join(String.duplicate(" ", @gap), fn {field, width} ->
      field |> value.() |> pad(field, width)
    end)
    |> String.trim_trailing()
  end

  # A number reads as a column when it ends where the others end.
  defp pad(text, %Field{type: :integer}, width), do: String.pad_leading(text, width)
  defp pad(text, _field, width), do: String.pad_trailing(text, width)

  defp width(field, records) do
    records
    |> Enum.map(&String.length(cell(field, &1)))
    |> Enum.max(fn -> 0 end)
    |> max(String.length(Field.short(field)))
    |> min(@max_column)
  end

  defp cell(%Field{type: Boolean} = field, record) do
    if record[field.key] == true, do: "[x]", else: "[ ]"
  end

  defp cell(field, record) do
    field |> Field.format(record[field.key]) |> one_line() |> clip()
  end

  # A field of several lines has to say what it says in one, along a row.
  defp one_line(value), do: value |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp clip(text) do
    if String.length(text) > @max_column,
      do: String.slice(text, 0, @max_column - 1) <> "…",
      else: text
  end

  ## Saying what happened

  defp line(schema, record) do
    case naming_field(schema) do
      nil -> "##{record[:id]}"
      field -> "##{record[:id]} #{one_line(Field.format(field, record[field.key]))}"
    end
  end

  defp message(_schema, reason) when is_binary(reason), do: reason

  defp message(schema, %Ecto.Changeset{} = changeset) do
    schema
    |> Schema.errors(changeset)
    |> Enum.map_join("; ", fn {field, message} -> "#{field.label} #{message}" end)
  end

  # Every one of them, or the first thing to go wrong — a command line that
  # was given three numbers has nothing to gain by failing three times.
  defp each(values, fun) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end
end
