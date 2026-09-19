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
      {:error, _reason} -> from_timestamp(value)
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

  @doc "A day as a column shows it, which is as it is stored."
  @spec format(String.t() | nil) :: String.t()
  def format(nil), do: ""
  def format(value) when is_binary(value), do: value
  def format(value), do: to_string(value)

  @doc "The width `format/1` needs, for laying out a column."
  @spec width() :: pos_integer()
  def width, do: 10

  defp from_timestamp(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> cast(at)
      {:error, _reason} -> :error
    end
  end
end
