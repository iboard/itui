defmodule ITui.Schema.Boolean do
  @moduledoc """
  An `Ecto.Type` for a yes/no field, in the words a person types.

  Ecto's own `:boolean` accepts `true`, `false`, `"1"` and `"0"`. A form in a
  terminal is answered by hand, so this one also takes `yes`, `no`, `y`, `n`,
  `on` and `off`, in any case — and says "must be yes or no" when it is given
  something else.

      iex> ITui.Schema.Boolean.cast("Yes")
      {:ok, true}

      iex> ITui.Schema.Boolean.cast("maybe")
      :error

  Stored and loaded as a plain JSON boolean.
  """

  use Ecto.Type

  @truthy ~w(true yes y 1 on)
  @falsy ~w(false no n 0 off)

  @impl Ecto.Type
  def type, do: :boolean

  @impl Ecto.Type
  def cast(value) when is_boolean(value), do: {:ok, value}

  def cast(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      truthy when truthy in @truthy -> {:ok, true}
      falsy when falsy in @falsy -> {:ok, false}
      _otherwise -> :error
    end
  end

  def cast(_value), do: :error

  @impl Ecto.Type
  def load(value) when is_boolean(value), do: {:ok, value}
  def load(_value), do: :error

  @impl Ecto.Type
  def dump(value) when is_boolean(value), do: {:ok, value}
  def dump(_value), do: :error
end
