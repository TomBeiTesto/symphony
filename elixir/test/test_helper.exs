exclude =
  if :os.type() == {:win32, :nt}, do: [:skip_on_windows], else: []

ExUnit.start(exclude: exclude)

# Define Mox mocks
Mox.defmock(SymphonyElixir.Tracker.MockClient, for: SymphonyElixir.Tracker.Behaviour)

defmodule SymphonyElixir.TestHelpers do
  @moduledoc "Shared test utilities."

  @doc """
  Polls `fun` every `interval` ms until it returns a truthy value or `timeout` ms elapse.
  Returns the truthy value on success, raises on timeout.
  """
  def wait_until(fun, timeout \\ 5_000, interval \\ 50) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(fun, deadline, interval)
  end

  defp do_wait_until(fun, deadline, interval) do
    case fun.() do
      nil -> maybe_retry(fun, deadline, interval)
      false -> maybe_retry(fun, deadline, interval)
      result -> result
    end
  end

  defp maybe_retry(fun, deadline, interval) do
    if System.monotonic_time(:millisecond) >= deadline do
      raise "wait_until timed out"
    else
      Process.sleep(interval)
      do_wait_until(fun, deadline, interval)
    end
  end
end
