defmodule SymphonyElixir.AppServer.ClaudeAdapter do
  @moduledoc """
  Claude Code subprocess adapter.

  Spawns `claude -p --output-format stream-json --verbose` and writes the
  prompt to stdin.  Reads newline-delimited JSON (NDJSON) from stdout.
  Each invocation is a single turn — Claude Code does not support the
  multi-turn app-server JSON-RPC protocol used by Codex.
  """

  require Logger

  alias SymphonyElixir.Config

  @max_line_bytes 10 * 1024 * 1024
  @default_command "claude"

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
          callback: (map() -> :ok),
          provider: :claude_code,
          prompt_file: String.t() | nil,
          accumulated_tokens: %{input: non_neg_integer(), output: non_neg_integer()}
        }

  # --- Public API (mirrors AppServer.Client) ---

  @doc "Start a Claude Code session — spawns the subprocess with the prompt."
  @spec start_session(Config.t(), String.t(), String.t(), (map() -> :ok)) ::
          {:ok, session()} | {:error, term()}
  def start_session(%Config{} = config, workspace_path, prompt, callback) do
    claude_cmd = resolve_command(config)
    prompt_file = Path.join(workspace_path, ".symphony_prompt_#{:rand.uniform(999_999)}.txt")

    case File.write(prompt_file, prompt) do
      :ok ->
        do_start_session(config, workspace_path, prompt_file, claude_cmd, callback)

      {:error, reason} ->
        {:error, {:prompt_write_failed, reason}}
    end
  end

  defp do_start_session(config, workspace_path, prompt_file, claude_cmd, callback) do
    # Always use bash for spawning — it handles stdin redirection, .cmd shims,
    # and EOF signaling correctly on both Windows and Unix.
    bash = find_bash()

    unless bash do
      cleanup_prompt_file(prompt_file)
      raise "bash not found — install Git for Windows or add bash to PATH"
    end

    # Build allowed tools flag if configured
    allowed_tools_flag = build_allowed_tools_flag()

    # Shell command: pipe prompt file into claude via stdin redirection
    shell_command =
      "cat #{shell_escape(prompt_file)} | #{claude_cmd} -p --output-format stream-json --verbose#{allowed_tools_flag} 2>&1"

    Logger.info("Claude adapter command: bash -lc '#{shell_command}'")
    Logger.info("Claude adapter workspace: #{workspace_path}")

    Logger.info(
      "Claude adapter prompt file: #{prompt_file} (#{byte_size(File.read!(prompt_file))} bytes)"
    )

    # Unset CLAUDECODE env var so nested Claude Code sessions are allowed.
    # Claude Code refuses to start if it detects it's inside another session.
    env = [
      {String.to_charlist("CLAUDECODE"), false},
      {String.to_charlist("CLAUDE_CODE_ENTRYPOINT"), false}
    ]

    port_opts = [
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      {:cd, workspace_path},
      {:args, ["-lc", shell_command]},
      {:env, env},
      {:line, @max_line_bytes}
    ]

    try do
      port = Port.open({:spawn_executable, bash}, port_opts)
      {:os_pid, os_pid} = Port.info(port, :os_pid)

      session_id = "claude-#{:rand.uniform(999_999)}"

      session = %{
        port: port,
        os_pid: os_pid,
        thread_id: session_id,
        turn_id: "turn-1",
        session_id: session_id,
        turn_count: 1,
        buffer: "",
        config: config,
        workspace_path: workspace_path,
        callback: callback,
        provider: :claude_code,
        prompt_file: prompt_file,
        accumulated_tokens: %{input: 0, output: 0}
      }

      emit_event(session, :session_started, %{os_pid: os_pid, provider: :claude_code})
      {:ok, session}
    rescue
      ErlangError ->
        cleanup_prompt_file(prompt_file)
        {:error, :agent_not_found}

      e ->
        cleanup_prompt_file(prompt_file)
        {:error, {:agent_not_found, Exception.message(e)}}
    end
  end

  @doc """
  Continuation turns for Claude Code.

  Claude --print is one-shot, so we spawn a fresh subprocess with a
  continuation prompt. The workspace state is preserved on disk.
  """
  @spec start_continuation_turn(session(), String.t()) :: {:ok, session()} | {:error, term()}
  def start_continuation_turn(session, continuation_prompt) do
    stop(session)

    case start_session(
           session.config,
           session.workspace_path,
           continuation_prompt,
           session.callback
         ) do
      {:ok, new_session} ->
        {:ok, %{new_session | turn_count: session.turn_count + 1}}

      error ->
        error
    end
  end

  @doc "Stream events from the current Claude Code turn until completion."
  @spec stream_turn(session()) ::
          {:ok, :completed | :failed | :cancelled, session()} | {:error, term()}
  def stream_turn(session) do
    deadline = System.monotonic_time(:millisecond) + session.config.turn_timeout_ms
    do_stream(session, deadline)
  end

  @doc "Stop the session, killing the subprocess."
  @spec stop(session()) :: :ok
  def stop(%{port: nil} = session) do
    cleanup_prompt_file(session[:prompt_file])
    :ok
  end

  def stop(%{port: port} = session) do
    try do
      Port.close(port)
    catch
      :error, :badarg -> :ok
    end

    cleanup_prompt_file(session[:prompt_file])
    emit_event(session, :session_stopped, %{})
    :ok
  end

  # --- Streaming ---

  defp do_stream(session, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      emit_event(session, :turn_timeout, %{})
      {:error, :turn_timeout}
    else
      timeout = min(remaining, 1000)

      receive do
        {port, {:data, {:eol, line}}} when port == session.port ->
          handle_line(session, line, deadline)

        {port, {:data, {:noeol, chunk}}} when port == session.port ->
          session = %{session | buffer: session.buffer <> chunk}
          do_stream(session, deadline)

        {port, {:exit_status, 0}} when port == session.port ->
          # Drain any remaining data from the mailbox
          session = drain_data(session)
          emit_event(session, :turn_completed, %{})
          {:ok, :completed, %{session | port: nil}}

        {port, {:exit_status, status}} when port == session.port ->
          # Drain any remaining data from the mailbox
          session = drain_data(session)

          if session.buffer != "" do
            Logger.error(
              "Claude adapter output before exit: #{String.slice(session.buffer, 0, 2000)}"
            )
          end

          Logger.error("Claude adapter exited with status #{status}")
          emit_event(session, :port_exit, %{status: status})
          {:error, :port_exit}
      after
        timeout ->
          do_stream(session, deadline)
      end
    end
  end

  # Drain any remaining port data messages from the mailbox
  defp drain_data(session) do
    receive do
      {port, {:data, {:eol, line}}} when port == session.port ->
        full_line = session.buffer <> line
        session = %{session | buffer: ""}

        case Jason.decode(full_line) do
          {:ok, msg} ->
            drain_data(process_ndjson_message(session, msg))

          {:error, _} ->
            if String.trim(full_line) != "" do
              Logger.warning("Claude adapter non-JSON output: #{String.slice(full_line, 0, 500)}")
            end

            drain_data(session)
        end

      {port, {:data, {:noeol, chunk}}} when port == session.port ->
        drain_data(%{session | buffer: session.buffer <> chunk})
    after
      0 -> session
    end
  end

  defp handle_line(session, raw_line, deadline) do
    line = session.buffer <> raw_line
    session = %{session | buffer: ""}

    case Jason.decode(line) do
      {:ok, msg} ->
        session = process_ndjson_message(session, msg)
        do_stream(session, deadline)

      {:error, _} ->
        if String.trim(line) != "" do
          Logger.warning("Claude adapter non-JSON output: #{String.slice(line, 0, 500)}")
          emit_event(session, :agent_output, %{line: String.slice(line, 0, 500)})
        end

        do_stream(session, deadline)
    end
  end

  defp process_ndjson_message(session, %{"type" => "assistant"} = msg) do
    message_text =
      case msg do
        %{"message" => %{"content" => content}} when is_list(content) ->
          content
          |> Enum.filter(&(&1["type"] == "text"))
          |> Enum.map_join("\n", & &1["text"])

        %{"content_block" => %{"text" => text}} ->
          text

        _ ->
          nil
      end

    if message_text && String.trim(message_text) != "" do
      Logger.info("[Claude] #{String.slice(message_text, 0, 500)}")
      emit_event(session, :agent_message, %{message: String.slice(message_text, 0, 2000)})
    end

    # Also log and emit tool use events
    case msg do
      %{"message" => %{"content" => content}} when is_list(content) ->
        content
        |> Enum.filter(&(&1["type"] == "tool_use"))
        |> Enum.each(fn tool ->
          input = tool["input"] || %{}
          detail = summarize_tool_input(tool["name"], input)
          Logger.info("[Claude] Using tool: #{tool["name"]} #{detail}")
          emit_event(session, :tool_use, %{tool: tool["name"], detail: detail, input: input})
        end)

      _ ->
        :ok
    end

    # Note: assistant message usage fields contain per-content-block fragments
    # (not cumulative totals). Real totals come from the "result" message.
    # We accumulate fragments into session to emit meaningful running totals.
    usage = get_in(msg, ["message", "usage"]) || msg["usage"] || %{}
    session = accumulate_streaming_tokens(session, usage)

    session
  end

  defp process_ndjson_message(session, %{"type" => "result"} = msg) do
    result_text = get_in(msg, ["result"]) || ""

    if result_text != "" do
      Logger.info("[Claude] Result: #{String.slice(result_text, 0, 300)}")
      emit_event(session, :agent_result, %{result: result_text})
    end

    # Log all top-level keys (except result text) to discover token fields
    debug_keys = Map.drop(msg, ["result", "type"]) |> inspect(limit: 500)
    Logger.info("[Claude] Result metadata: #{debug_keys}")

    # Aggregate real token totals from modelUsage (per-model breakdown with camelCase keys)
    usage = aggregate_model_usage(msg["modelUsage"]) || msg["usage"] || msg["total_usage"] || %{}
    emit_token_usage(session, usage)
    session
  end

  defp process_ndjson_message(session, %{"type" => "system"} = msg) do
    session_id = msg["session_id"] || session.session_id

    # Only emit system_info once (first time we see it)
    if session.session_id != session_id do
      Logger.info("[Claude] Session started: #{session_id}")

      emit_event(session, :system_info, %{
        session_id: session_id,
        tools: msg["tools"] || []
      })
    end

    %{session | session_id: session_id}
  end

  # Handle content_block_start with tool_use — captures tool name from streaming
  defp process_ndjson_message(session, %{
         "type" => "content_block_start",
         "content_block" => %{"type" => "tool_use"} = block
       }) do
    Logger.info("[Claude] Tool start: #{block["name"]}")
    emit_event(session, :tool_use, %{tool: block["name"], detail: ""})
    session
  end

  # Handle message_delta which may carry usage info (fragments, not cumulative)
  defp process_ndjson_message(session, %{"type" => "message_delta"} = msg) do
    accumulate_streaming_tokens(session, msg["usage"] || %{})
  end

  defp process_ndjson_message(session, msg) do
    Logger.debug("[Claude] NDJSON: type=#{msg["type"] || "unknown"}")
    session
  end

  # Accumulate streaming token fragments into a running total and emit periodically.
  # Streaming events send per-content-block fragments (not cumulative totals).
  defp accumulate_streaming_tokens(session, usage) when map_size(usage) == 0, do: session

  defp accumulate_streaming_tokens(session, usage) do
    delta_in = usage["input_tokens"] || 0
    delta_out = usage["output_tokens"] || 0

    acc = session.accumulated_tokens
    new_acc = %{input: acc.input + delta_in, output: acc.output + delta_out}
    session = %{session | accumulated_tokens: new_acc}

    # Emit accumulated totals (cumulative) so the orchestrator's delta tracking works correctly
    if new_acc.input > 0 or new_acc.output > 0 do
      emit_event(session, :token_usage_updated, %{
        input_tokens: new_acc.input,
        output_tokens: new_acc.output,
        total_tokens: new_acc.input + new_acc.output
      })
    end

    session
  end

  # Aggregate token usage from modelUsage map (per-model breakdown with camelCase keys)
  defp aggregate_model_usage(nil), do: nil
  defp aggregate_model_usage(model_usage) when not is_map(model_usage), do: nil

  defp aggregate_model_usage(model_usage) do
    initial = %{"input_tokens" => 0, "output_tokens" => 0}

    totals =
      Enum.reduce(model_usage, initial, fn {_model, usage}, acc ->
        input =
          (usage["inputTokens"] || 0) +
            (usage["cacheReadInputTokens"] || 0) +
            (usage["cacheCreationInputTokens"] || 0)

        output = usage["outputTokens"] || 0

        %{
          "input_tokens" => acc["input_tokens"] + input,
          "output_tokens" => acc["output_tokens"] + output
        }
      end)

    if totals["input_tokens"] > 0 or totals["output_tokens"] > 0, do: totals, else: nil
  end

  # Emit final token usage from result metadata (real totals, not streaming fragments)
  defp emit_token_usage(_session, usage) when map_size(usage) == 0, do: :ok

  defp emit_token_usage(session, usage) do
    input = usage["input_tokens"] || 0
    output = usage["output_tokens"] || 0

    if input > 0 or output > 0 do
      Logger.info("[Claude] Final tokens: #{input} in / #{output} out")

      emit_event(session, :token_usage_updated, %{
        input_tokens: input,
        output_tokens: output,
        total_tokens: input + output
      })
    end
  end

  # --- Command Building ---

  defp find_bash do
    System.find_executable("bash") ||
      find_file([
        "C:/Program Files/Git/bin/bash.exe",
        "C:/Program Files (x86)/Git/bin/bash.exe",
        "C:/msys64/usr/bin/bash.exe",
        "C:/cygwin64/bin/bash.exe"
      ])
  end

  defp find_file([]), do: nil

  defp find_file([path | rest]) do
    if File.exists?(path), do: path, else: find_file(rest)
  end

  defp build_allowed_tools_flag do
    tools =
      try do
        SymphonyElixir.Settings.get("agent_allowed_tools") || ""
      catch
        :exit, _ -> ""
      end

    if tools != "" do
      # Split comma-separated list and build repeated --allowedTools flags
      tools
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map_join("", fn tool -> " --allowedTools '#{tool}'" end)
    else
      ""
    end
  end

  defp resolve_command(%Config{agent_command: cmd}) when is_binary(cmd) and cmd != "" do
    if String.contains?(cmd, "claude") do
      cmd
    else
      @default_command
    end
  end

  defp resolve_command(_config), do: @default_command

  defp shell_escape(path) do
    # Convert Windows backslash paths to forward slashes for bash
    path
    |> String.replace("\\", "/")
    |> then(&"\"#{&1}\"")
  end

  defp cleanup_prompt_file(nil), do: :ok

  defp cleanup_prompt_file(path) do
    File.rm(path)
    :ok
  end

  # --- Helpers ---

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp summarize_tool_input(tool_name, input) do
    case tool_name do
      "WebSearch" -> input["query"] || ""
      "WebFetch" -> input["url"] |> to_string() |> String.slice(0, 120)
      "Read" -> input["file_path"] || ""
      "Write" -> input["file_path"] || ""
      "Edit" -> input["file_path"] || ""
      "Glob" -> input["pattern"] || ""
      "Grep" -> input["pattern"] || ""
      "Bash" -> input["command"] |> to_string() |> String.slice(0, 200)
      "ToolSearch" -> input["query"] || ""
      _ -> input |> inspect() |> String.slice(0, 200)
    end
  end

  defp emit_event(%{callback: callback} = session, event, payload) do
    callback.(%{
      event: event,
      timestamp: DateTime.utc_now(),
      agent_process_pid: session.os_pid,
      session_id: session.session_id,
      payload: payload
    })
  end
end
