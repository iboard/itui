defmodule ITui do
  @moduledoc """
  iTUI — a configurable terminal UI for Linux.

  iTUI turns plain text files into a working terminal application: a structured
  menu that runs system commands and applications, and simple forms that collect
  the parameters those commands need. Menus, forms and data structures are
  described by JSON schemas in `data/schemas/`, and rendered with
  [ATUI](https://hexdocs.pm/atui).

  ## Version

  Returns the version of the running application.

      iex> ITui.version() =~ ~r/^\\d+\\.\\d+\\.\\d+/
      true

  """

  @doc """
  The version of the `:i_tui` application, as declared in `mix.exs`.
  """
  @spec version() :: String.t()
  def version do
    :i_tui |> Application.spec(:vsn) |> to_string()
  end
end
