exclude = if :os.type() == {:win32, :nt}, do: [:skip_on_windows], else: []

ExUnit.start(exclude: exclude)

# Define Mox mocks
Mox.defmock(SymphonyElixir.Tracker.MockClient, for: SymphonyElixir.Tracker.Behaviour)

defmodule SymphonyElixir.TestHelpers do
  @moduledoc "Shared test utilities."

  @doc """
  Polls `fun` every `interval` ms until it returns a truthy value or `timeout` ms elapse.
  Returns the truthy value on success, raises on timeout.
  """
  def wait_until(fun, timeout \\ 5_000, interval \\ 50, label \\ nil) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(fun, deadline, interval, label)
  end

  defp do_wait_until(fun, deadline, interval, label) do
    case fun.() do
      nil -> maybe_retry(fun, deadline, interval, label)
      false -> maybe_retry(fun, deadline, interval, label)
      result -> result
    end
  end

  defp maybe_retry(fun, deadline, interval, label) do
    if System.monotonic_time(:millisecond) >= deadline do
      message = if label, do: "wait_until timed out: #{label}", else: "wait_until timed out"
      raise message
    else
      Process.sleep(interval)
      do_wait_until(fun, deadline, interval, label)
    end
  end
end
