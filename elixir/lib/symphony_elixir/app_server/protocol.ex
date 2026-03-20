defmodule SymphonyElixir.AppServer.Protocol do
  @moduledoc """
  JSON-RPC-like message builders for the coding agent app-server protocol.

  See SPEC Section 10.2 - 10.5.
  """

  alias SymphonyElixir.LocalBoard.Helpers

  @type message :: map()

  @doc "Build an `initialize` request."
  @spec initialize(pos_integer()) :: message()
  def initialize(id \\ 1) do
    %{
      "id" => id,
      "method" => "initialize",
      "params" => %{
        "clientInfo" => %{"name" => "symphony", "version" => SymphonyElixir.version()},
        "capabilities" => %{}
      }
    }
  end

  @doc "Build an `initialized` notification."
  @spec initialized() :: message()
  def initialized do
    %{
      "method" => "initialized",
      "params" => %{}
    }
  end

  @doc "Build a `thread/start` request."
  @spec thread_start(pos_integer(), map()) :: message()
  def thread_start(id \\ 2, opts) do
    %{
      "id" => id,
      "method" => "thread/start",
      "params" =>
        %{
          "approvalPolicy" => opts[:approval_policy] || "auto-edit",
          "sandbox" => opts[:thread_sandbox] || "stateless",
          "cwd" => opts[:cwd]
        }
        |> Helpers.maybe_put("tools", opts[:tools])
    }
  end

  @doc "Build a `turn/start` request."
  @spec turn_start(pos_integer(), map()) :: message()
  def turn_start(id \\ 3, opts) do
    %{
      "id" => id,
      "method" => "turn/start",
      "params" => %{
        "threadId" => opts[:thread_id],
        "input" => [%{"type" => "text", "text" => opts[:prompt]}],
        "cwd" => opts[:cwd],
        "title" => opts[:title],
        "approvalPolicy" => opts[:approval_policy] || "auto-edit",
        "sandboxPolicy" => opts[:sandbox_policy] || %{"type" => "stateless"}
      }
    }
  end

  @doc "Build an approval result response."
  @spec approval_result(String.t(), boolean()) :: message()
  def approval_result(approval_id, approved \\ true) do
    %{
      "id" => approval_id,
      "result" => %{"approved" => approved}
    }
  end

  @doc "Build a tool call failure response for unsupported tools."
  @spec tool_call_failure(String.t(), String.t()) :: message()
  def tool_call_failure(tool_call_id, error \\ "unsupported_tool_call") do
    %{
      "id" => tool_call_id,
      "result" => %{"success" => false, "error" => error}
    }
  end

  @doc "Encode a message to a line-delimited JSON string."
  @spec encode(message()) :: {:ok, String.t()} | {:error, term()}
  def encode(msg) do
    case Jason.encode(msg) do
      {:ok, json} -> {:ok, json <> "\n"}
      error -> error
    end
  end

  @doc "Decode a single line of JSON into a message."
  @spec decode(String.t()) :: {:ok, message()} | {:error, term()}
  def decode(line) do
    line
    |> String.trim()
    |> Jason.decode()
  end

  @doc "Classify an incoming message by method or event type."
  @spec classify(message()) :: atom()
  def classify(msg) do
    method = msg["method"] || ""

    cond do
      # Responses to our requests (have "id" and "result" or "error")
      Map.has_key?(msg, "result") and Map.has_key?(msg, "id") ->
        :response

      method == "turn/completed" ->
        :turn_completed

      method == "turn/failed" ->
        :turn_failed

      method == "turn/cancelled" ->
        :turn_cancelled

      method == "item/tool/requestUserInput" ->
        :turn_input_required

      method == "thread/tokenUsage/updated" ->
        :token_usage_updated

      method =~ "approval" ->
        :approval_request

      method == "item/tool/call" ->
        :tool_call

      method == "notification" ->
        :notification

      method != "" ->
        :other_message

      true ->
        :malformed
    end
  end

  @doc "Extract thread ID from a thread/start response."
  @spec extract_thread_id(message()) :: String.t() | nil
  def extract_thread_id(%{"result" => %{"thread" => %{"id" => id}}}), do: id
  def extract_thread_id(%{"result" => %{"id" => id}}), do: id
  def extract_thread_id(_), do: nil

  @doc "Extract turn ID from a turn/start response."
  @spec extract_turn_id(message()) :: String.t() | nil
  def extract_turn_id(%{"result" => %{"turn" => %{"id" => id}}}), do: id
  def extract_turn_id(%{"result" => %{"id" => id}}), do: id
  def extract_turn_id(_), do: nil

  @doc "Extract token usage from a token usage event."
  @spec extract_token_usage(message()) :: map() | nil
  def extract_token_usage(%{"params" => params}) when is_map(params) do
    usage =
      params["totalTokenUsage"] ||
        params["total_token_usage"] ||
        params["usage"] ||
        params

    case usage do
      %{} = u ->
        %{
          input_tokens: u["inputTokens"] || u["input_tokens"] || 0,
          output_tokens: u["outputTokens"] || u["output_tokens"] || 0,
          total_tokens: u["totalTokens"] || u["total_tokens"] || 0
        }

      _ ->
        nil
    end
  end

  def extract_token_usage(_), do: nil

  @doc "Extract rate limit info from agent events."
  @spec extract_rate_limits(message()) :: map() | nil
  def extract_rate_limits(%{"params" => %{"rateLimits" => rl}}) when is_map(rl), do: rl
  def extract_rate_limits(%{"params" => %{"rate_limits" => rl}}) when is_map(rl), do: rl
  def extract_rate_limits(_), do: nil

end
