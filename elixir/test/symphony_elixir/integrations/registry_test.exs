defmodule SymphonyElixir.Integrations.RegistryTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Integrations.Registry

  @settings_store "test_registry_settings_#{System.unique_integer([:positive])}.json"

  setup do
    start_supervised!({SymphonyElixir.Settings, store_path: @settings_store})
    on_exit(fn -> File.rm(@settings_store) end)
    :ok
  end

  describe "resolve / available_types" do
    test "available_types returns all four integration types" do
      types = Registry.available_types()
      assert "jira" in types
      assert "gitlab_ci" in types
      assert "confluence" in types
      assert "knowledge_base" in types
    end
  end

  describe "execute/3" do
    test "returns error for unknown integration type" do
      assert {:error, {:unknown_integration, "nonexistent"}} =
               Registry.execute("nonexistent", %{}, %{})
    end

    test "dispatches to knowledge_base module" do
      # KB with local type and test_connection-safe action
      config = %{"kb_type" => "local", "vault_path" => "", "action" => "search"}
      context = %{"query" => "nothing"}

      # Should not crash — delegates to KnowledgeBase.execute
      result = Registry.execute("knowledge_base", config, context)
      assert {:ok, _} = result
    end
  end

  describe "test_connection/2" do
    test "returns error for unknown integration type" do
      assert {:error, {:unknown_integration, "nonexistent"}} =
               Registry.test_connection("nonexistent")
    end

    test "knowledge_base test_connection works with local type" do
      SymphonyElixir.Settings.update(%{"kb_type" => "local"})
      assert {:ok, _message} = Registry.test_connection("knowledge_base")
    end
  end

  describe "build_config/2" do
    test "merges global credentials from Settings with action config" do
      SymphonyElixir.Settings.update(%{
        "jira_base_url" => "https://test.atlassian.net",
        "jira_auth_token" => "secret-token"
      })

      config = Registry.build_config("jira", %{"action" => "create", "issue_type" => "Bug"})

      assert config["base_url"] == "https://test.atlassian.net"
      assert config["auth_token"] == "secret-token"
      assert config["action"] == "create"
      assert config["issue_type"] == "Bug"
    end

    test "action config overrides credentials when keys collide" do
      SymphonyElixir.Settings.update(%{"gitlab_ci_ref" => "main"})

      config = Registry.build_config("gitlab_ci", %{"ref" => "develop"})
      assert config["ref"] == "develop"
    end

    test "omits empty credential values" do
      SymphonyElixir.Settings.update(%{"jira_base_url" => "", "jira_auth_token" => ""})

      config = Registry.build_config("jira")
      refute Map.has_key?(config, "base_url")
      refute Map.has_key?(config, "auth_token")
    end
  end

  describe "get_credentials/1" do
    test "strips type prefix from settings keys" do
      SymphonyElixir.Settings.update(%{
        "confluence_base_url" => "https://wiki.example.com",
        "confluence_space_key" => "ENG"
      })

      creds = Registry.get_credentials("confluence")
      assert creds["base_url"] == "https://wiki.example.com"
      assert creds["space_key"] == "ENG"
    end

    test "returns empty map for unknown type" do
      assert Registry.get_credentials("nonexistent") == %{}
    end
  end

end
