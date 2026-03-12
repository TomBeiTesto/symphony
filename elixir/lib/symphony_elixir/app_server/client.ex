defmodule SymphonyElixir.AppServer.Client do
  @moduledoc """
  Manages a coding agent app-server subprocess.

  Launches the agent process, performs the startup handshake, streams turn events,
  and handles continuation turns and cleanup.

  See SPEC Section 10.
  """

  require Logger

  alias SymphonyElixir.AppServer.{Events, Protocol}
  alias SymphonyElixir.{Config, ShellUtils}

  @max_line_bytes 10 * 1024 * 1024

  @type session :: %{
          port: port() | nil,
          os_pid: non_neg_integer() | nil,
          thread_id: String.t() | nil,
          turn_id: String.t() | nil,
          session_id: String.t() | nil,
          turn_count: non_neg_integer(),
          buffer: String.t(),
          config: Config.t(),
          workspace_path: String.t(),
          callback: (map() -> :ok)
        }

  # --- Public API ---

  @doc """
  Start a new app-server session. Launches the subprocess, performs the handshake,
  and returns the session state.
  """
  @spec start_session(Config.t(), String.t(), String.t(), (map() -> :ok)) ::
          {:ok, session()} | {:error, term()}
  def start_session(%Config{} = config, workspace_path, prompt, callback) do
    command = config.agent_command
    shell_args = ShellUtils.shell_args(shell_executable(config))

    port_opts = [
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      {:cd, workspace_path},
      {:args, shell_args ++ [command]},
      {:line, @max_line_bytes}
    ]

    shell_cmd = shell_executable(config)

    try do
      port = Port.open({:spawn_executable, shell_cmd}, port_opts)
      {:os_pid, os_pid} = Port.info(port, :os_pid)

      session = %{
        port: port,
        os_pid: os_pid,
        thread_id: nil,
        turn_id: nil,
        session_id: nil,
        turn_count: 0,
        buffer: "",
        config: config,
        workspace_path: workspace_path,
        callback: callback
      }

      with {:ok, session} <- do_handshake(session, prompt) do
        Events.emit_event(session, :session_started, %{os_pid: os_pid})
        {:ok, session}
      end
    rescue
      ErlangError ->
        {:error, :agent_not_found}

      e ->
        {:error, {:agent_not_found, Exception.message(e)}}
    end
  end

  @doc "Start a continuation turn on an existing session."
  @spec start_continuation_turn(session(), String.t()) :: {:ok, session()} | {:error, term()}
  def start_continuation_turn(%{thread_id: tid} = session, continuation_prompt)
      when is_binary(tid) do
    msg =
      Protocol.turn_start(session.turn_count + 3, %{
        thread_id: tid,
        prompt: continuation_prompt,
        cwd: session.workspace_path,
        title: "",
        approval_policy: session.config.approval_policy,
        sandbox_policy: build_sandbox_policy(session.config)
      })

    with :ok <- send_message(session, msg),
         {:ok, resp} <- read_response(session, session.config.read_timeout_ms) do
      turn_id = Protocol.extract_turn_id(resp)
      session_id = "#{tid}-#{turn_id}"

      {:ok,
       %{
         session
         | turn_id: turn_id,
           session_id: session_id,
           turn_count: session.turn_count + 1
       }}
    end
  end

  @doc "Stream events from the current turn until completion."
  @spec stream_turn(session()) ::
          {:ok, :completed | :failed | :cancelled, session()} | {:error, term()}
  def stream_turn(session) do
    deadline = System.monotonic_time(:millisecond) + session.config.turn_timeout_ms
    do_stream_turn(session, deadline)
  end

  @doc "Stop the session, killing the subprocess."
  @spec stop(session()) :: :ok
  def stop(%{port: nil}), do: :ok

  def stop(%{port: port} = session) do
    try do
      Port.close(port)
    catch
      :error, :badarg -> :ok
    end

    Events.emit_event(session, :session_stopped, %{})
    :ok
  end

  # --- Handshake ---

  defp do_handshake(session, prompt) do
    read_timeout = session.config.read_timeout_ms

    with :ok <- send_message(session, Protocol.initialize()),
         {:ok, _init_resp} <- read_response(session, read_timeout),
         :ok <- send_message(session, Protocol.initialized()),
         :ok <-
           send_message(
             session,
             Protocol.thread_start(2, %{
               cwd: session.workspace_path,
               approval_policy: session.config.approval_policy,
               thread_sandbox: session.config.thread_sandbox
             })
           ),
         {:ok, thread_resp} <- read_response(session, read_timeout) do
      thread_id = Protocol.extract_thread_id(thread_resp)

      if is_nil(thread_id) do
        {:error, :response_error}
      else
        title = Map.get(session, :title, "")

        turn_msg =
          Protocol.turn_start(3, %{
            thread_id: thread_id,
            prompt: prompt,
            cwd: session.workspace_path,
            title: title,
            approval_policy: session.config.approval_policy,
            sandbox_policy: build_sandbox_policy(session.config)
          })

        with :ok <- send_message(session, turn_msg),
             {:ok, turn_resp} <- read_response(session, read_timeout) do
          turn_id = Protocol.extract_turn_id(turn_resp)
          session_id = "#{thread_id}-#{turn_id}"

          {:ok,
           %{
             session
             | thread_id: thread_id,
               turn_id: turn_id,
               session_id: session_id,
               turn_count: 1
           }}
        end
      end
    end
  end

  # --- Streaming ---

  defp do_stream_turn(session, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      Events.emit_event(session, :turn_timeout, %{})
      {:error, :turn_timeout}
    else
      timeout = min(remaining, 1000)

      receive do
        {port, {:data, {:eol, line}}} when port == session.port ->
          handle_line(session, line, deadline)

        {port, {:data, {:noeol, chunk}}} when port == session.port ->
          session = %{session | buffer: session.buffer <> chunk}
          do_stream_turn(session, deadline)

        {port, {:exit_status, status}} when port == session.port ->
          if status == 0 do
            {:ok, :completed, %{session | port: nil}}
          else
            Events.emit_event(session, :port_exit, %{status: status})
            {:error, :port_exit}
          end
      after
        timeout ->
          do_stream_turn(session, deadline)
      end
    end
  end

  defp handle_line(session, raw_line, deadline) do
    line = session.buffer <> raw_line
    session = %{session | buffer: ""}

    case Protocol.decode(line) do
      {:ok, msg} ->
        session = process_message(session, msg)

        case Protocol.classify(msg) do
          :turn_completed ->
            Events.emit_event(session, :turn_completed, %{})
            {:ok, :completed, session}

          :turn_failed ->
            Events.emit_event(session, :turn_failed, %{message: inspect(msg)})
            {:ok, :failed, session}

          :turn_cancelled ->
            Events.emit_event(session, :turn_cancelled, %{})
            {:ok, :cancelled, session}

          :turn_input_required ->
            Events.emit_event(session, :turn_input_required, %{})
            {:error, :turn_input_required}

          :approval_request ->
            approval_id = msg["id"]

            if approval_id do
              send_message(session, Protocol.approval_result(approval_id, true))
              Events.emit_event(session, :approval_auto_approved, %{id: approval_id})
            end

            do_stream_turn(session, deadline)

          :tool_call ->
            tool_call_id = msg["id"]

            if tool_call_id do
              handle_tool_call(session, msg)
            end

            do_stream_turn(session, deadline)

          _ ->
            do_stream_turn(session, deadline)
        end

      {:error, _} ->
        Events.emit_event(session, :malformed, %{line: String.slice(line, 0, 200)})
        do_stream_turn(session, deadline)
    end
  end

  defp process_message(session, msg) do
    # Update token usage if present
    case Protocol.extract_token_usage(msg) do
      %{} = usage ->
        Events.emit_event(session, :token_usage_updated, usage)

      nil ->
        :ok
    end

    # Update rate limits if present
    case Protocol.extract_rate_limits(msg) do
      %{} = rl ->
        Events.emit_event(session, :rate_limits_updated, rl)

      nil ->
        :ok
    end

    session
  end

  defp handle_tool_call(session, msg) do
    tool_name = get_in(msg, ["params", "name"]) || ""
    tool_call_id = msg["id"]

    send_message(session, Protocol.tool_call_failure(tool_call_id))
    Events.emit_event(session, :unsupported_tool_call, %{tool: tool_name})
  end

  # --- Message I/O ---

  defp send_message(%{port: port}, msg) do
    case Protocol.encode(msg) do
      {:ok, data} ->
        Port.command(port, data)
        :ok

      {:error, reason} ->
        {:error, {:encode_error, reason}}
    end
  end

  defp read_response(session, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_read_response(session, deadline)
  end

  defp do_read_response(session, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :response_timeout}
    else
      timeout = min(remaining, 100)

      receive do
        {port, {:data, {:eol, line}}} when port == session.port ->
          full_line = session.buffer <> line

          case Protocol.decode(full_line) do
            {:ok, %{"result" => _} = msg} ->
              {:ok, msg}

            {:ok, %{"error" => err}} ->
              {:error, {:response_error, err}}

            {:ok, _notification} ->
              # Skip notifications, keep waiting for response
              do_read_response(%{session | buffer: ""}, deadline)

            {:error, _} ->
              do_read_response(%{session | buffer: ""}, deadline)
          end

        {port, {:data, {:noeol, chunk}}} when port == session.port ->
          do_read_response(%{session | buffer: session.buffer <> chunk}, deadline)

        {port, {:exit_status, _}} when port == session.port ->
          {:error, :port_exit}
      after
        timeout ->
          do_read_response(session, deadline)
      end
    end
  end

  # --- Helpers ---

  defp shell_executable(%Config{} = config) do
    case config.agent_shell do
      nil -> ShellUtils.default_shell()
      shell -> shell
    end
  end

  defp build_sandbox_policy(%Config{} = config) do
    config.turn_sandbox_policy || %{"type" => "stateless"}
  end
end
