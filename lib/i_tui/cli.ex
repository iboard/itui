defmodule ITui.CLI do
  @moduledoc """
  The escript: iTUI as one executable file.

      mix escript.build     # ./itui
      mix escript.install   # ~/.mix/escripts/itui

  The VM is started with `+Bc`, so Ctrl-C reaches the application rather than
  opening the BEAM's BREAK menu, and the application is not started before
  `main/1` — otherwise `--version` would open a terminal UI to say a number.
  """

  # Read here rather than from the application spec: `app: nil` means the
  # application is not even loaded when a flag is answered.
  @version Mix.Project.config()[:version]

  @doc """
  Runs iTUI, or answers for it.
  """
  @spec main([String.t()]) :: :ok
  def main(argv)

  def main([]), do: run()

  def main([flag]) when flag in ["-v", "--version"], do: IO.puts("iTUI #{@version}")

  def main([flag]) when flag in ["-h", "--help"], do: IO.puts(help())

  # Loaded, not started: saying where the data is should not open a UI over it.
  def main([flag]) when flag in ["-w", "--where"] do
    :ok = load()

    IO.puts(ITui.Data.resolve!())
  end

  def main(argv) do
    IO.puts(:stderr, "iTUI: I do not know what to do with #{Enum.join(argv, " ")}\n")
    IO.puts(:stderr, help())

    System.halt(1)
  end

  defp run do
    {:ok, _apps} = Application.ensure_all_started(:i_tui)

    # The UI has the terminal and the VM stops with it; this is only here so
    # that the escript does not fall off the end of main/1 and take it away.
    ref = Process.monitor(Atui.Runtime)

    receive do
      {:DOWN, ^ref, :process, _runtime, _reason} -> :ok
    end
  end

  defp load do
    case Application.load(:i_tui) do
      :ok -> :ok
      {:error, {:already_loaded, :i_tui}} -> :ok
      error -> error
    end
  end

  defp help do
    """
    iTUI — a configurable terminal UI for Linux.

      itui              open the menu
      itui --where      say which data directory it is using
      itui --version    say which version this is
      itui --help       this

    The menus and schemas are JSON files in the data directory: $ITUI_DATA if
    it is set, ~/.itui if that is where you keep it, and ~/.config/itui
    otherwise. The ones that ship with iTUI are written there on first run,
    and yours are left alone after that.
    """
  end
end
