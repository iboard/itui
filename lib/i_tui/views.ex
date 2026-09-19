defmodule ITui.Views do
  @moduledoc """
  The applications a menu entry can open, by the name it calls them.

  A menu file says `"view": "todo"`, not a module name: the file is
  configuration, and configuration that can name any module in the VM is not
  configuration any more. This is the list of what a menu is allowed to open.
  """

  @views %{"todo" => ITui.Views.Todo}

  @doc """
  The view module called `name`.

      iex> ITui.Views.fetch("todo")
      {:ok, ITui.Views.Todo}

      iex> ITui.Views.fetch("spreadsheet")
      {:error, ~s(unknown view "spreadsheet"; known views: todo)}

  """
  @spec fetch(String.t()) :: {:ok, module()} | {:error, String.t()}
  def fetch(name) when is_binary(name) do
    case Map.fetch(@views, name) do
      {:ok, module} ->
        {:ok, module}

      :error ->
        {:error, ~s(unknown view "#{name}"; known views: #{Enum.join(known(), ", ")})}
    end
  end

  @doc "The names a menu file may use."
  @spec known() :: [String.t()]
  def known, do: @views |> Map.keys() |> Enum.sort()
end
