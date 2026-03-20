defmodule SymphonyElixir.LLM do
  @moduledoc """
  Lightweight Anthropic Messages API client for server-side LLM calls.

  Used for tasks like KB note merging where spawning a full agent is overkill.
  Reads ANTHROPIC_API_KEY from the environment.
  """

  require Logger

  alias SymphonyElixir.LocalBoard.Helpers

  @api_url "https://api.anthropic.com/v1/messages"
  @default_model "claude-sonnet-4-20250514"
  @default_max_tokens 4096
  @timeout 120_000

  @doc """
  Send a prompt to the Anthropic Messages API and return the text response.

  Options:
    - :model — model ID (default: #{@default_model})
    - :max_tokens — max response tokens (default: #{@default_max_tokens})
    - :system — system prompt string
  """
  @spec call(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def call(prompt, opts \\ []) do
    api_key = System.get_env("ANTHROPIC_API_KEY") || ""

    if api_key == "" do
      {:error, :no_api_key}
    else
      model = Keyword.get(opts, :model, @default_model)
      max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
      system_prompt = Keyword.get(opts, :system)

      body =
        %{
          "model" => model,
          "max_tokens" => max_tokens,
          "messages" => [%{"role" => "user", "content" => prompt}]
        }
        |> Helpers.maybe_put("system", if(system_prompt in [nil, ""], do: nil, else: system_prompt))

      headers = [
        {"x-api-key", api_key},
        {"anthropic-version", "2023-06-01"},
        {"content-type", "application/json"}
      ]

      case Req.post(@api_url, json: body, headers: headers, receive_timeout: @timeout) do
        {:ok, %Req.Response{status: 200, body: resp_body}} ->
          text =
            resp_body
            |> Map.get("content", [])
            |> Enum.find_value("", fn block ->
              if block["type"] == "text", do: block["text"]
            end)

          {:ok, text}

        {:ok, %Req.Response{status: status, body: resp_body}} ->
          Logger.warning("LLM API error #{status}: #{inspect(resp_body)}")
          {:error, {:api_error, status, resp_body}}

        {:error, reason} ->
          Logger.warning("LLM API request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

end
