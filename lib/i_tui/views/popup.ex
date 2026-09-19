defmodule ITui.Views.Popup do
  @moduledoc """
  The one message a pushed view sends back to the view that pushed it.

  `Atui` stacks views, and the root view sees every key before the focused one
  does — so the root has to know whether something is open above it, or it
  moves a cursor nobody can see. Nothing tells it when a view it pushed is
  gone, so the view says so itself, on its way out:

      {:popup_closed, module, result}

  It is sent from `c:Atui.View.unmount/1`, which the runtime calls for a pop, a
  quit and a shutdown alike, so it arrives exactly once however the view ends.
  `result` is what the view was opened for: `:ok` when it was only shown,
  `{:submitted, attrs}` or `:cancelled` from a form.
  """

  @type result :: :ok | :cancelled | {:submitted, map()}

  @doc """
  Tells `notify` something while the popup is still open.

  The same delivery as `closed/3`, for a popup whose work is worth watching as
  it happens rather than only when it is over — a filter, say, with the list it
  filters still on the screen behind it.
  """
  @spec tell(module() | nil, term()) :: :ok
  def tell(nil, _message), do: :ok

  def tell(notify, message) when is_atom(notify) do
    Atui.Runtime.send_event_to(self(), notify, message)

    :ok
  end

  @doc """
  Tells `notify` that `module` has closed. Call it from `unmount/1`.
  """
  @spec closed(module() | nil, module(), result()) :: :ok
  def closed(nil, _module, _result), do: :ok

  def closed(notify, module, result) when is_atom(notify) do
    Atui.Runtime.send_event_to(self(), notify, {:popup_closed, module, result})

    :ok
  end
end
