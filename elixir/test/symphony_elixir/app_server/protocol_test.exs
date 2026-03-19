defmodule SymphonyElixir.AppServer.ProtocolTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.AppServer.Protocol

  describe "initialize/1" do
    test "builds an initialize request message" do
      msg = Protocol.initialize(1)
      assert msg["id"] == 1
      assert msg["method"] == "initialize"
      assert msg["params"]["clientInfo"]["name"] == "symphony"
      assert is_map(msg["params"]["capabilities"])
    end
  end

  describe "initialized/0" do
    test "builds an initialized notification" do
      msg = Protocol.initialized()
      assert msg["method"] == "initialized"
      refute Map.has_key?(msg, "id")
    end
  end

  describe "thread_start/2" do
    test "builds a thread/start request" do
      msg = Protocol.thread_start(2, %{cwd: "/workspace", approval_policy: "auto-edit"})
      assert msg["id"] == 2
      assert msg["method"] == "thread/start"
      assert msg["params"]["cwd"] == "/workspace"
      assert msg["params"]["approvalPolicy"] == "auto-edit"
    end
  end

  describe "turn_start/2" do
    test "builds a turn/start request with prompt" do
      msg =
        Protocol.turn_start(3, %{
          thread_id: "thread-1",
          prompt: "Do something",
          cwd: "/workspace",
          title: "MT-123: Test",
          approval_policy: "auto-edit"
        })

      assert msg["id"] == 3
      assert msg["method"] == "turn/start"
      assert msg["params"]["threadId"] == "thread-1"
      assert [%{"type" => "text", "text" => "Do something"}] = msg["params"]["input"]
      assert msg["params"]["title"] == "MT-123: Test"
    end
  end

  describe "approval_result/2" do
    test "builds an approval response" do
      msg = Protocol.approval_result("approval-1", true)
      assert msg["id"] == "approval-1"
      assert msg["result"]["approved"] == true
    end
  end

  describe "tool_call_failure/2" do
    test "builds a tool call failure response" do
      msg = Protocol.tool_call_failure("tool-1")
      assert msg["id"] == "tool-1"
      assert msg["result"]["success"] == false
      assert msg["result"]["error"] == "unsupported_tool_call"
    end

    test "allows custom error message" do
      msg = Protocol.tool_call_failure("tool-1", "custom_error")
      assert msg["result"]["error"] == "custom_error"
    end
  end

  describe "encode/1 and decode/1" do
    test "roundtrips a message through encode/decode" do
      msg = Protocol.initialize()
      assert {:ok, json} = Protocol.encode(msg)
      assert String.ends_with?(json, "\n")
      assert {:ok, decoded} = Protocol.decode(json)
      assert decoded["method"] == "initialize"
    end

    test "encode produces valid JSON line" do
      msg = %{"id" => 1, "method" => "test"}
      assert {:ok, json} = Protocol.encode(msg)
      assert {:ok, _} = Jason.decode(String.trim(json))
    end

    test "decode handles whitespace" do
      assert {:ok, msg} = Protocol.decode(~s(  {"method":"test"}  \n))
      assert msg["method"] == "test"
    end

    test "decode returns error for invalid JSON" do
      assert {:error, _} = Protocol.decode("not json")
    end
  end

  describe "classify/1" do
    test "classifies response messages" do
      assert :response == Protocol.classify(%{"id" => 1, "result" => %{}})
    end

    test "classifies turn/completed" do
      assert :turn_completed == Protocol.classify(%{"method" => "turn/completed"})
    end

    test "classifies turn/failed" do
      assert :turn_failed == Protocol.classify(%{"method" => "turn/failed"})
    end

    test "classifies turn/cancelled" do
      assert :turn_cancelled == Protocol.classify(%{"method" => "turn/cancelled"})
    end

    test "classifies turn_input_required" do
      assert :turn_input_required ==
               Protocol.classify(%{"method" => "item/tool/requestUserInput"})
    end

    test "classifies token_usage_updated" do
      assert :token_usage_updated ==
               Protocol.classify(%{"method" => "thread/tokenUsage/updated"})
    end

    test "classifies approval_request" do
      assert :approval_request == Protocol.classify(%{"method" => "approval/request"})
    end

    test "classifies tool_call" do
      assert :tool_call == Protocol.classify(%{"method" => "item/tool/call"})
    end

    test "classifies notification" do
      assert :notification == Protocol.classify(%{"method" => "notification"})
    end

    test "classifies other_message for unknown methods" do
      assert :other_message == Protocol.classify(%{"method" => "unknown/method"})
    end

    test "classifies malformed for messages without method" do
      assert :malformed == Protocol.classify(%{"data" => "something"})
    end
  end

  describe "extract_thread_id/1" do
    test "extracts from nested thread object" do
      resp = %{"result" => %{"thread" => %{"id" => "thread-abc"}}}
      assert "thread-abc" == Protocol.extract_thread_id(resp)
    end

    test "extracts from flat result id" do
      resp = %{"result" => %{"id" => "thread-abc"}}
      assert "thread-abc" == Protocol.extract_thread_id(resp)
    end

    test "returns nil for missing data" do
      assert nil == Protocol.extract_thread_id(%{})
    end
  end

  describe "extract_turn_id/1" do
    test "extracts from nested turn object" do
      resp = %{"result" => %{"turn" => %{"id" => "turn-abc"}}}
      assert "turn-abc" == Protocol.extract_turn_id(resp)
    end
  end

  describe "extract_token_usage/1" do
    test "extracts from totalTokenUsage" do
      msg = %{
        "params" => %{
          "totalTokenUsage" => %{
            "inputTokens" => 100,
            "outputTokens" => 50,
            "totalTokens" => 150
          }
        }
      }

      usage = Protocol.extract_token_usage(msg)
      assert usage.input_tokens == 100
      assert usage.output_tokens == 50
      assert usage.total_tokens == 150
    end

    test "extracts from snake_case fields" do
      msg = %{
        "params" => %{
          "total_token_usage" => %{
            "input_tokens" => 200,
            "output_tokens" => 100,
            "total_tokens" => 300
          }
        }
      }

      usage = Protocol.extract_token_usage(msg)
      assert usage.input_tokens == 200
    end

    test "returns nil for messages without token data" do
      assert nil == Protocol.extract_token_usage(%{})
      assert nil == Protocol.extract_token_usage(%{"params" => "string"})
    end
  end

  describe "extract_rate_limits/1" do
    test "extracts camelCase rate limits" do
      msg = %{"params" => %{"rateLimits" => %{"remaining" => 100}}}
      assert %{"remaining" => 100} = Protocol.extract_rate_limits(msg)
    end

    test "extracts snake_case rate limits" do
      msg = %{"params" => %{"rate_limits" => %{"remaining" => 50}}}
      assert %{"remaining" => 50} = Protocol.extract_rate_limits(msg)
    end

    test "returns nil when no rate limits" do
      assert nil == Protocol.extract_rate_limits(%{"params" => %{}})
    end
  end
end
