defmodule ITui.CLI do
  @moduledoc """
  The escript: iTUI as one executable file, and what it takes on the line.

      mix escript.build     # ./itui
      mix escript.install   # ~/.mix/escripts/itui

  Some of what iTUI does wants a screen, and some of it is a sentence:

      itui                                     open the menu
      itui menu system/uptime                  open it there, and run it
      itui todo                                open the todo list
      itui todo add "Buy milk" --due tomorrow  add one, and stop
      itui todo done 3                         check it off, and stop
      itui todo list --hide done               print them, and stop
      itui --help                              all of it, at length

  The two are one command because they are one application: the menu, the
  schema and the records a command reads are the ones the screen shows.
  `itui --help` — `ITui.CLI.Help` — says the whole of it, with the options
  `todo add` takes read from the schema itself.

  ## How it runs

  The VM is started with `+Bc`, so Ctrl-C reaches the application rather than
  opening the BEAM's BREAK menu, and the application is not started before
  `main/1` — otherwise `--version` would open a terminal UI to say a number.
  The commands that want a screen start it with `:view_opts` saying where to
  open (see `ITui.Views.MainMenu`); the rest never start it at all, and say
  what they have to say on standard output.
  """

  alias ITui.CLI.{Help, Todo}
  alias ITui.{Data, Menu, Schema}

  # Read here rather than from the application spec: `app: nil` means the
  # application is not even loaded when a flag is answered.
  @version Mix.Project.config()[:version]

  @doc """
  Runs iTUI, or answers for it.
  """
  @spec main([String.t()]) :: :ok
  def main(argv) do
    case command(argv) do
      {:open, opts} -> open(opts)
      {:say, text} -> IO.puts(text)
      {:error, message} -> abort(message)
    end
  end

  @doc """
  Does what `argv` asks, as far as it can be done without a screen, and says
  what is left to do about it:

    * `{:open, opts}` — open the UI, mounting the menu with `opts`
    * `{:say, text}` — print this, and stop
    * `{:error, message}` — this went wrong

  Adding a todo, checking one off and listing them are all done by the time
  this returns; `main/1` only prints the answer and chooses an exit status.
  """
  @spec command([String.t()]) :: {:open, keyword()} | {:say, String.t()} | {:error, String.t()}
  def command(argv)

  def command([]), do: {:open, []}

  def command([flag]) when flag in ["-v", "--version"], do: {:say, "iTUI #{@version}"}

  def command([flag]) when flag in ["-h", "--help"], do: {:say, Help.text(schema())}

  # Loaded, not started: saying where the data is should not open a UI over it.
  def command([flag]) when flag in ["-w", "--where"], do: {:say, data!()}

  def command(["menu" | rest]), do: menu(rest)

  def command(["todo" | rest]), do: todo(rest)

  def command(argv), do: {:error, ~s(I do not know what to do with "#{Enum.join(argv, " ")}")}

  # The path is resolved before the UI is started, so a name that is not in
  # the menu is a line on the terminal rather than a popup over one.
  defp menu(argv) do
    case segments(argv) do
      [] ->
        {:open, []}

      segments ->
        data!()

        with {:ok, menu} <- Menu.load(),
             {:ok, _chain} <- Menu.resolve(menu.items, segments) do
          {:open, [open: segments]}
        end
    end
  end

  # "system/uptime" and "system uptime" are the same path said two ways.
  defp segments(argv), do: argv |> Enum.join("/") |> String.split("/", trim: true)

  defp todo([]), do: {:open, [open_view: "todo"]}
  defp todo(["list" | rest]), do: with_schema(&Todo.list(&1, rest))
  defp todo(["add" | rest]), do: with_schema(&Todo.add(&1, rest))
  defp todo(["done" | rest]), do: with_schema(&Todo.check(&1, rest))

  defp todo(argv) do
    {:error,
     ~s(itui todo: I do not know what "#{Enum.join(argv, " ")}" means; ) <>
       "it takes list, add and done"}
  end

  defp with_schema(fun) do
    data!()

    with {:ok, schema} <- Schema.load("todo"), do: fun.(schema)
  end

  # The schema as far as the help is concerned: a file that cannot be read
  # leaves the options out of the help rather than making it an error.
  defp schema do
    data!()

    case Schema.load("todo") do
      {:ok, schema} -> schema
      {:error, _reason} -> nil
    end
  end

  # Where the data lives, written out if it is not there yet, remembered for
  # everything that reads a menu or a schema afterwards.
  defp data! do
    :ok = load()

    Data.resolve!()
  end

  defp open(opts) do
    Application.put_env(:i_tui, :view_opts, opts)

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

  defp abort(message) do
    IO.puts(:stderr, "itui: #{message}")
    IO.puts(:stderr, "\nitui --help says what it takes.")

    System.halt(1)
  end
end
