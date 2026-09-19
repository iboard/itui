defmodule ITui.Application do
  @moduledoc """
  The OTP application: it starts the terminal UI under its own supervisor.

  The UI is a child spec like any other, so quitting it stops that child and,
  with `Atui`'s default `halt: :system`, the VM with it. Set
  `config :i_tui, start_ui: false` to load the application without taking the
  terminal — which is what the test suite does, driving views headlessly
  instead.
  """

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(children(), strategy: :one_for_one, name: ITui.Supervisor)
  end

  defp children do
    if Application.get_env(:i_tui, :start_ui, true) do
      [{Atui, view: ITui.Views.MainMenu}]
    else
      []
    end
  end
end
