defmodule ITui.Band do
  @moduledoc """
  What kind of todo a todo is: done, overdue, due this week, and the rest.

  A band is worked out from the record rather than stored on it — whether it
  is ticked, and how near its `due` date is to today. It is what
  `ITui.Views.Todo` colours a row by, what `ITui.Views.Filter` hides and shows,
  and what `itui todo list --only overdue` means, so the three of them say the
  same thing by saying it in one place.

      iex> ITui.Band.of(nil, %{done: true}, ~D[2026-09-19])
      :done

  The ladder goes from the nearest to the furthest off, which is the order the
  filter lists them in:

  | | |
  | --- | --- |
  | `done` | ticked off, whenever it was due |
  | `overdue` | the day has gone by |
  | `soon` | due within two days |
  | `week` | due in what is left of this calendar week |
  | `month` | due in what is left of this month |
  | `later` | due after that |
  | `none` | not due on any particular day |
  """

  alias ITui.Schema

  @bands [
    {:done, "Done"},
    {:overdue, "Overdue"},
    {:soon, "Due within two days"},
    {:week, "Due this week"},
    {:month, "Due this month"},
    {:later, "Due later"},
    {:none, "No due date"}
  ]

  # Near enough to be worth a warning of its own.
  @soon_days 2

  @type t :: :done | :overdue | :soon | :week | :month | :later | :none

  @doc """
  Every band with the name it is shown by, nearest first.
  """
  @spec list() :: [{t(), String.t()}]
  def list, do: @bands

  @doc """
  The names a command line may use for them.

      iex> ITui.Band.names()
      ["done", "overdue", "soon", "week", "month", "later", "none"]

  """
  @spec names() :: [String.t()]
  def names, do: Enum.map(@bands, fn {band, _label} -> Atom.to_string(band) end)

  @doc """
  The band called `name`.

      iex> ITui.Band.fetch("overdue")
      {:ok, :overdue}

      iex> ITui.Band.fetch("urgent")
      {:error, ~s(there is no "urgent" kind of todo; there is: done, overdue, soon, week, month, later, none)}

  """
  @spec fetch(String.t()) :: {:ok, t()} | {:error, String.t()}
  def fetch(name) when is_binary(name) do
    case Enum.find(@bands, fn {band, _label} -> Atom.to_string(band) == name end) do
      {band, _label} ->
        {:ok, band}

      nil ->
        {:error, ~s(there is no "#{name}" kind of todo; there is: #{Enum.join(names(), ", ")})}
    end
  end

  @doc """
  What kind of todo `todo` is, reckoned from `today`.

  A ticked todo is done whatever its date says; the rest are placed by how
  near the day in the schema's `due` field is — and a schema without one, or
  a todo with nothing in it, is due on no particular day.

      iex> {:ok, schema} = ITui.Schema.load("todo")
      iex> ITui.Band.of(schema, %{due: "2026-09-18"}, ~D[2026-09-19])
      :overdue

  """
  @spec of(Schema.t() | nil, map(), Date.t()) :: t()
  def of(schema, todo, today) do
    if done?(todo), do: :done, else: due(due_date(schema, todo), today)
  end

  @doc "True for a todo that is ticked off."
  @spec done?(map()) :: boolean()
  def done?(todo), do: todo[:done] == true

  defp due_date(nil, _todo), do: nil

  defp due_date(schema, todo) do
    case Schema.field(schema, :due) do
      nil -> nil
      field -> ITui.Schema.Date.parse(todo[field.key])
    end
  end

  defp due(nil, _today), do: :none

  defp due(date, today) do
    cond do
      Date.before?(date, today) -> :overdue
      Date.diff(date, today) <= @soon_days -> :soon
      not Date.after?(date, Date.end_of_week(today)) -> :week
      not Date.after?(date, Date.end_of_month(today)) -> :month
      true -> :later
    end
  end
end
