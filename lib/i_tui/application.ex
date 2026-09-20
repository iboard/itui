defmodule ITui.Application do
  @moduledoc """
  The OTP application: it starts the terminal UI under its own supervisor.

  The UI is a child spec like any other, so quitting it stops that child and,
  with `Atui`'s default `halt: :system`, the VM with it. Set
  `config :i_tui, start_ui: false` to load the application without taking the
  terminal — which is what the test suite does, driving views headlessly
  instead.

  Before the UI starts, `ITui.Data.resolve!/0` works out where the menus and
  schemas live and writes out the ones that are missing, so that an escript
  with no data directory beside it has one by the time a menu is read.

  `config :i_tui, view_opts: [...]` is passed to the root view's `mount/1`.
  That is how `ITui.CLI` says where to open — a menu entry named on the
  command line, or the todo list — since the application is what starts the
  UI and the arguments arrive before it does.
  """

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(children(), strategy: :one_for_one, name: ITui.Supervisor)
  end

  defp children do
    if Application.get_env(:i_tui, :start_ui, true) do
      ITui.Data.resolve!()

      [{Atui, view: ITui.Views.MainMenu, view_opts: view_opts()}]
    else
      []
    end
  end

  defp view_opts, do: Application.get_env(:i_tui, :view_opts, [])
end
