defmodule ITui.Schema.Timestamp do
  @moduledoc """
  An `Ecto.Type` for a moment in time, kept as an ISO 8601 string in UTC.

  A record is a JSON object, so a timestamp is stored the way the repository
  already stores `inserted_at`: `"2026-09-19T19:26:18Z"`. That makes it one
  thing in the file, in the changeset and in a sort — ISO 8601 in UTC sorts
  lexicographically, which is chronologically.

      iex> ITui.Schema.Timestamp.cast("2026-09-19T19:26:18Z")
      {:ok, "2026-09-19T19:26:18Z"}

      iex> ITui.Schema.Timestamp.cast("last tuesday")
      :error

  It is shown as the local day it fell on, because that is the timezone the
  person reading the screen is in, and the day is what a list is read by.
  """

  use Ecto.Type

  @impl Ecto.Type
  def type, do: :string

  @impl Ecto.Type
  def cast(nil), do: {:ok, nil}
  def cast(""), do: {:ok, nil}
  def cast(%DateTime{} = at), do: {:ok, encode(at)}

  def cast(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, encode(at)}
      {:error, _reason} -> :error
    end
  end

  def cast(_value), do: :error

  @impl Ecto.Type
  def load(value) when is_binary(value) or is_nil(value), do: {:ok, value}
  def load(_value), do: :error

  @impl Ecto.Type
  def dump(value) when is_binary(value) or is_nil(value), do: {:ok, value}
  def dump(_value), do: :error

  @doc "Now, in the form a record keeps it."
  @spec now() :: String.t()
  def now, do: encode(DateTime.utc_now())

  @doc """
  A timestamp as a column shows it: `2026-09-19`, the local day it fell on.

  The time of day is in the record, and in the file; a list of what happened
  and when is read by the day, and the hours cost it four columns of width.

      iex> ITui.Schema.Timestamp.format(nil)
      ""

  """
  @spec format(String.t() | nil) :: String.t()
  def format(nil), do: ""
  def format(""), do: ""

  def format(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> at |> local() |> render()
      {:error, _reason} -> value
    end
  end

  def format(value), do: to_string(value)

  @doc "The width `format/1` needs, for laying out a column."
  @spec width() :: pos_integer()
  def width, do: 10

  defp encode(%DateTime{} = at) do
    at |> DateTime.truncate(:second) |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_iso8601()
  end

  # OTP knows the machine's timezone and its daylight saving, for the date in
  # question rather than for today, so no timezone database is needed here.
  defp local(%DateTime{} = at) do
    :calendar.universal_time_to_local_time(
      {{at.year, at.month, at.day}, {at.hour, at.minute, at.second}}
    )
  end

  defp render({{year, month, day}, {_hour, _minute, _second}}) do
    "#{year}-#{pad(month)}-#{pad(day)}"
  end

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")
end
