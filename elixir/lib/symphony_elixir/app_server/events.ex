defmodule SymphonyElixir.AppServer.Events do
  @moduledoc """
  Shared event emission for app-server adapters.

  Both `AppServer.Client` and `AppServer.ClaudeAdapter` use the same
  event structure; this module provides a single implementation.
  """

  @doc """
  Emit a structured event via the session callback.

  The session map must contain `:callback`, `:os_pid`, and `:session_id`.
  """
  @spec emit_event(map(), atom(), map()) :: :ok
  def emit_event(%{callback: callback} = session, event, payload) do
    callback.(%{
      event: event,
      timestamp: DateTime.utc_now(),
      agent_process_pid: session.os_pid,
      session_id: session.session_id,
      payload: payload
    })
  end
end
