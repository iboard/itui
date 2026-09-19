defmodule ITui.Data do
  @moduledoc """
  Where the menus, the schemas and the records live.

  iTUI is installed as a package, so there is no directory beside it to read:
  the menus and schemas that ship with it are read into the code at compile
  time and written into the home directory on first run. After that they are
  ordinary files on disk, to be edited — which is the point of describing an
  application in JSON rather than in code.

  Where they live, in order:

    * `$ITUI_DATA`, for a directory said outright
    * `~/.itui`, if that is where you keep it
    * `~/.config/itui` — or `$XDG_CONFIG_HOME/itui` — which is the default

  A file that is already there is never written over, so an upgrade that adds
  a schema adds it, and an edited menu stays edited. The records go in there
  too: a schema's `source` is a path inside this directory.
  """

  @bundled_files Path.wildcard("data/{menus,schemas}/*.json")

  for path <- @bundled_files do
    @external_resource path
  end

  @bundled Map.new(@bundled_files, fn path ->
             {Path.relative_to(path, "data"), File.read!(path)}
           end)

  @doc """
  The data directory in use.

  Whatever `resolve!/0` decided, or the configured one before it has run.
  """
  @spec dir() :: Path.t()
  def dir, do: Application.get_env(:i_tui, :data_dir, "data")

  @doc """
  Works out where the data lives, writing out what is missing, and remembers it.

  Called once as the application starts, before anything reads a menu.
  """
  @spec resolve!() :: Path.t()
  def resolve! do
    dir = chosen()

    install!(dir)
    Application.put_env(:i_tui, :data_dir, dir)

    dir
  end

  @doc """
  Writes the files that ship with iTUI into `dir`, leaving alone any that are
  already there.

  Returns the paths it wrote.
  """
  @spec install!(Path.t()) :: [Path.t()]
  def install!(dir) do
    for {path, contents} <- @bundled, not File.exists?(Path.join(dir, path)) do
      full = Path.join(dir, path)

      File.mkdir_p!(Path.dirname(full))
      File.write!(full, contents)

      full
    end
  end

  @doc """
  The files iTUI carries with it: menus and schemas, by their path under the
  data directory.
  """
  @spec bundled() :: %{Path.t() => String.t()}
  def bundled, do: @bundled

  @doc """
  A path named by a schema, against the data directory.

  A schema says `records/todos.json` — where its records go inside the data
  directory — and an absolute path is taken as it stands.
  """
  @spec path(Path.t()) :: Path.t()
  def path(path) do
    if Path.type(path) == :absolute, do: path, else: Path.join(dir(), path)
  end

  defp chosen do
    said = System.get_env("ITUI_DATA")
    dotted = home(".itui")

    cond do
      is_binary(said) and said != "" -> said
      File.dir?(dotted) -> dotted
      true -> config_home()
    end
  end

  defp config_home do
    case System.get_env("XDG_CONFIG_HOME") do
      nil -> home(".config/itui")
      "" -> home(".config/itui")
      xdg -> Path.join(xdg, "itui")
    end
  end

  defp home(path), do: Path.join(System.user_home!(), path)
end
