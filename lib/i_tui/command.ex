defmodule ITui.Command do
  @moduledoc """
  A system command a menu entry runs, and the running of it.

  A command is data — a program name and its arguments — so a menu can be
  described in a JSON file and still say exactly what it will execute. The
  program is never handed to a shell: `run/1` resolves it with
  `System.find_executable/1` and passes the arguments straight to
  `System.cmd/3`, so nothing in a menu file can be expanded, globbed or chained.

      iex> ITui.Command.new("df", ["-h"]) |> ITui.Command.to_string()
      "df -h"

  `run/1` blocks until the command finishes, so a view runs it through
  `Atui.Fetch` rather than inside a callback.
  """

  defstruct [:program, args: []]

  @type t :: %__MODULE__{program: String.t(), args: [String.t()]}

  @doc """
  Builds a command from a program name and its arguments.

      iex> ITui.Command.new("uptime")
      %ITui.Command{program: "uptime", args: []}

  """
  @spec new(String.t(), [String.t()]) :: t()
  def new(program, args \\ []) when is_binary(program) and is_list(args) do
    %__MODULE__{program: program, args: args}
  end

  @doc """
  The command as it would be typed, for showing next to a menu entry.
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{program: program, args: args}) do
    Enum.join([program | args], " ")
  end

  @doc """
  Fills the `{{placeholders}}` in the arguments from a form's values.

  A menu entry that names a form says where the values go by writing the field
  names into its arguments; a placeholder with nothing to fill it becomes an
  empty argument, which is why a field a command needs should be required.

      iex> ITui.Command.new("ping", ["-c", "{{count}}", "{{host}}"])
      ...> |> ITui.Command.render(%{"count" => 3, "host" => "example.com"})
      ...> |> ITui.Command.to_string()
      "ping -c 3 example.com"

  """
  @spec render(t(), map()) :: t()
  def render(%__MODULE__{} = command, params) when is_map(params) do
    %{command | args: Enum.map(command.args, &fill(&1, params))}
  end

  @doc """
  Runs the command and captures its output.

  Returns `{:ok, output}` when the command exits with status 0, and
  `{:error, message}` when the program is missing, cannot be started, or exits
  with any other status — in which case its own output is part of the message,
  because that is where a command explains itself.

  Standard error is captured along with standard output: a user who asked for
  `df` wants to see "permission denied" as much as the table.
  """
  @spec run(t()) :: {:ok, String.t()} | {:error, String.t()}
  def run(%__MODULE__{program: program, args: args}) do
    case System.find_executable(program) do
      nil ->
        {:error, "command not found: #{program}"}

      path ->
        case System.cmd(path, args, stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          {output, status} -> {:error, "#{program} exited with status #{status}\n\n#{output}"}
        end
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp fill(arg, params) do
    Regex.replace(~r/\{\{([a-zA-Z0-9_]+)\}\}/, arg, fn _match, name ->
      Kernel.to_string(Map.get(params, name, ""))
    end)
  end
end
