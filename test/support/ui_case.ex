defmodule ITui.UICase do
  @moduledoc """
  Drives a view through a headless `Atui.Runtime`.

  `:headless` renders into memory instead of a terminal and `:size` fixes the
  viewport, so a test can press keys and read the frame back as text without a
  tty in sight. The runtime registers itself under its own module name, so
  these tests are not `async`.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import ITui.UICase

      alias Atui.Runtime
    end
  end

  @doc """
  Starts a headless runtime with `view` as the root view.

  `halt: :stop` keeps a `q` in a test from stopping the VM along with the UI,
  and `Atui`'s child spec is `:temporary`, so a UI that has quit is not
  restarted underneath the test that quit it.
  """
  def start_ui(view, opts \\ []) do
    {size, opts} = Keyword.pop(opts, :size, {70, 20})

    ExUnit.Callbacks.start_supervised!(
      {Atui, [view: view, view_opts: opts, headless: true, halt: :stop, size: size]}
    )
  end

  @doc "Presses `keys` in order, and returns what is on screen afterwards."
  def press(runtime, keys) when is_list(keys) do
    Enum.each(keys, &Atui.Runtime.send_key(runtime, &1))

    text(runtime)
  end

  def press(runtime, key), do: press(runtime, [key])

  @doc "Types `text` one character at a time, as a keyboard would."
  def type(runtime, text) do
    press(runtime, text |> String.graphemes() |> Enum.map(&{:char, &1}))
  end

  @doc """
  Lets the runtime finish what the last key set in motion, and returns the
  frame.

  A popup's parting message (`Atui.Popup`) is sent while the key that
  closed it is being handled, which puts it behind whatever the test has
  already asked for. One more round trip is what makes it arrive.
  """
  def settle(runtime) do
    text(runtime)
    text(runtime)
  end

  @doc "The last rendered frame as plain text, escape sequences stripped."
  def text(runtime), do: runtime |> Atui.Runtime.screen() |> Atui.Screen.to_text()

  @doc """
  Waits for `module` to be the view on top, for a popup that opens on its own.

  Waiting on the stack rather than on the text keeps a test from matching
  something the view underneath happens to be showing already.
  """
  def await_view(runtime, module, timeout \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    wait_view(runtime, module, deadline)
  end

  defp wait_view(runtime, module, deadline) do
    case Atui.Runtime.view_stack(runtime) do
      [^module | _rest] ->
        text(runtime)

      stack ->
        if System.monotonic_time(:millisecond) >= deadline do
          ExUnit.Assertions.flunk("waited for #{inspect(module)}, stack is #{inspect(stack)}")
        else
          Process.sleep(10)
          wait_view(runtime, module, deadline)
        end
    end
  end

  @doc """
  Waits for the screen to match `pattern`, for output that arrives on its own.

  A command runs in a process of its own, so the frame showing what it printed
  is a few milliseconds behind the key that asked for it.
  """
  def await_text(runtime, pattern, timeout \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    wait(runtime, pattern, deadline)
  end

  defp wait(runtime, pattern, deadline) do
    screen = text(runtime)

    cond do
      screen =~ pattern -> screen
      System.monotonic_time(:millisecond) >= deadline -> flunk(runtime, pattern, screen)
      true -> Process.sleep(10) && wait(runtime, pattern, deadline)
    end
  end

  defp flunk(runtime, pattern, screen) do
    ExUnit.Assertions.flunk("""
    waited for #{inspect(pattern)}, but the screen still reads:

    #{screen}
    view stack: #{inspect(Atui.Runtime.view_stack(runtime))}
    """)
  end
end
