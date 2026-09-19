defmodule ITui.Schema.Date do
  @moduledoc """
  An `Ecto.Type` for a day, kept as `YYYY-MM-DD`.

  A due date is a day in a calendar rather than a moment in time: it is typed
  by hand, it is read by the day, and it must not shift by one when a timezone
  is applied to it. So it is stored as a plain ISO 8601 date — which, like
  `ITui.Schema.Timestamp`, sorts lexicographically because it sorts
  chronologically.

      iex> ITui.Schema.Date.cast("2026-09-25")
      {:ok, "2026-09-25"}

      iex> ITui.Schema.Date.cast("25.09.2026")
      :error

  A full timestamp casts to the day it fell on, so a column can be moved from
  one type to the other without rewriting the file.

  ## Saying when without looking it up

  Nobody knows what date a fortnight on Tuesday is, so a day can also be given
  as how far off it is and worked out from today:

      in 3 days · 3 days · 3d · +3d · 3weeks · 1 month · -2w · 2 years
      today · tomorrow · yesterday

  Months and years land on the same day of the month, or the last one there is
  — the 31st of January in a month is the 28th of February. What is stored is
  the day it came to, because that is what was meant; `relative/2` says it the
  other way round again for a list.
  """

  use Ecto.Type

  @impl Ecto.Type
  def type, do: :string

  @impl Ecto.Type
  def cast(nil), do: {:ok, nil}
  def cast(""), do: {:ok, nil}
  def cast(%Date{} = date), do: {:ok, Date.to_iso8601(date)}
  def cast(%DateTime{} = at), do: {:ok, at |> DateTime.to_date() |> Date.to_iso8601()}

  def cast(value) when is_binary(value) do
    value = String.trim(value)

    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, Date.to_iso8601(date)}
      {:error, _reason} -> with :error <- from_timestamp(value), do: from_words(value)
    end
  end

  def cast(_value), do: :error

  @impl Ecto.Type
  def load(value) when is_binary(value) or is_nil(value), do: {:ok, value}
  def load(_value), do: :error

  @impl Ecto.Type
  def dump(value) when is_binary(value) or is_nil(value), do: {:ok, value}
  def dump(_value), do: :error

  @doc "Today, as a stored day is written."
  @spec today() :: String.t()
  def today, do: Date.to_iso8601(local_today())

  @doc """
  The day it is where the person reading the screen is.
  """
  @spec local_today() :: Date.t()
  def local_today, do: NaiveDateTime.local_now() |> NaiveDateTime.to_date()

  @doc """
  The stored day as a `Date`, or `nil` for anything that is not one.

      iex> ITui.Schema.Date.parse("2026-09-25")
      ~D[2026-09-25]

      iex> ITui.Schema.Date.parse("soon")
      nil

  """
  @spec parse(term()) :: Date.t() | nil
  def parse(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  def parse(_value), do: nil

  @doc """
  A day as it stands from another one: `+3 days`, `-2 weeks`, `today`.

  The further off a day is, the coarser the unit it is worth saying in — a
  fortnight is easier to weigh up than fourteen days, and five months easier
  than a hundred and fifty. Days up to a fortnight, then weeks up to a month,
  then months up to a year, then years.

      iex> ITui.Schema.Date.relative(~D[2026-09-21], ~D[2026-09-19])
      "+2 days"

      iex> ITui.Schema.Date.relative(~D[2026-09-05], ~D[2026-09-19])
      "-2 weeks"

      iex> ITui.Schema.Date.relative(~D[2026-09-19], ~D[2026-09-19])
      "today"

  """
  @spec relative(Date.t() | nil, Date.t()) :: String.t()
  def relative(nil, _today), do: ""

  def relative(%Date{} = date, %Date{} = today) do
    case Date.diff(date, today) do
      0 -> "today"
      days when abs(days) <= 13 -> count(days, 1, "day")
      days when abs(days) <= 27 -> count(days, 7, "week")
      days when abs(days) <= 364 -> count(days, 30, "month")
      days -> count(days, 365, "year")
    end
  end

  @doc "A day as a column shows it, which is as it is stored."
  @spec format(String.t() | nil) :: String.t()
  def format(nil), do: ""
  def format(value) when is_binary(value), do: value
  def format(value), do: to_string(value)

  @doc "The width `format/1` needs, for laying out a column."
  @spec width() :: pos_integer()
  def width, do: 10

  @units %{
    "d" => :day,
    "day" => :day,
    "days" => :day,
    "w" => :week,
    "week" => :week,
    "weeks" => :week,
    "m" => :month,
    "mo" => :month,
    "month" => :month,
    "months" => :month,
    "y" => :year,
    "year" => :year,
    "years" => :year
  }

  @words %{"today" => 0, "tomorrow" => 1, "yesterday" => -1}

  @amount ~r/^([+-]?\d+)\s*([a-z]+)$/

  # "in 3 days" is how it is said; "in" carries nothing, so it is dropped.
  defp from_words(value) do
    said = value |> String.downcase() |> String.replace_prefix("in ", "") |> String.trim()

    case Map.fetch(@words, said) do
      {:ok, days} -> {:ok, shift(days, :day)}
      :error -> from_amount(said)
    end
  end

  defp from_amount(said) do
    with [_all, number, unit] <- Regex.run(@amount, said),
         {:ok, unit} <- Map.fetch(@units, unit) do
      {:ok, shift(String.to_integer(number), unit)}
    else
      _otherwise -> :error
    end
  end

  defp shift(n, :day), do: local_today() |> Date.add(n) |> Date.to_iso8601()
  defp shift(n, :week), do: local_today() |> Date.add(n * 7) |> Date.to_iso8601()
  defp shift(n, :month), do: local_today() |> Date.shift(month: n) |> Date.to_iso8601()
  defp shift(n, :year), do: local_today() |> Date.shift(year: n) |> Date.to_iso8601()

  # Rounded to the nearest whole unit, and never to nothing: a day and a half
  # away is "+1 day", not "today".
  defp count(days, per, unit) do
    n = max(round(abs(days) / per), 1)
    sign = if days < 0, do: "-", else: "+"

    "#{sign}#{n} #{unit}#{if n == 1, do: "", else: "s"}"
  end

  defp from_timestamp(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> cast(at)
      {:error, _reason} -> :error
    end
  end
end
