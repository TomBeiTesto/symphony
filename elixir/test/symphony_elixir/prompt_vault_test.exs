defmodule SymphonyElixir.PromptVaultTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.{Issue, Prompt, Settings}

  @settings_path "test_prompt_vault_settings_#{System.unique_integer([:positive])}.json"

  @issue %Issue{
    id: "abc123",
    identifier: "SYM-10",
    title: "Test vault context",
    state: "In Progress",
    labels: [],
    blocked_by: [],
    propose_followups: false
  }

  setup do
    start_supervised!({Settings, store_path: @settings_path})
    on_exit(fn -> File.rm(@settings_path) end)
    :ok
  end

  describe "vault context injection" do
    test "injects vault context when kb is configured" do
      Settings.update(%{
        "kb_type" => "obsidian",
        "kb_vault_path" => "C:/my/vault",
        "kb_subfolder" => "symphony"
      })

      template =
        "{% if vault %}VAULT={{ vault.path }}/{{ vault.subfolder }}{% endif %} Work on {{ issue.identifier }}."

      assert {:ok, rendered} = Prompt.render(template, @issue)
      assert rendered =~ "VAULT=/vault/symphony"
      assert rendered =~ "SYM-10"
    end

    test "skips vault context when kb_vault_path is empty" do
      Settings.update(%{"kb_type" => "obsidian", "kb_vault_path" => ""})

      template = "{% if vault %}HAS_VAULT{% endif %}Work on {{ issue.identifier }}."
      assert {:ok, rendered} = Prompt.render(template, @issue)
      refute rendered =~ "HAS_VAULT"
      assert rendered =~ "SYM-10"
    end

    test "injects vault context for local kb_type with vault_path" do
      Settings.update(%{
        "kb_type" => "local",
        "kb_vault_path" => "/tmp/kb",
        "kb_subfolder" => "my-kb"
      })

      template = "{% if vault %}VAULT={{ vault.path }}/{{ vault.subfolder }}{% endif %}"
      assert {:ok, rendered} = Prompt.render(template, @issue)
      assert rendered =~ "VAULT=/vault/my-kb"
    end

    test "injects vault context for local kb_type even without vault_path" do
      Settings.update(%{
        "kb_type" => "local",
        "kb_vault_path" => "",
        "kb_subfolder" => "symphony"
      })

      template = "{% if vault %}HAS_VAULT{% endif %}{{ issue.identifier }}"
      assert {:ok, rendered} = Prompt.render(template, @issue)
      assert rendered =~ "HAS_VAULT"
      assert rendered =~ "SYM-10"
    end
  end
end
