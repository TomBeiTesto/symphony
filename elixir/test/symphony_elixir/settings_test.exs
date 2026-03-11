defmodule SymphonyElixir.SettingsTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Settings

  @store_path "test_settings_#{System.unique_integer([:positive])}.json"

  setup do
    start_supervised!({Settings, store_path: @store_path})
    on_exit(fn -> File.rm(@store_path) end)
    :ok
  end

  describe "all/0" do
    test "returns defaults on fresh start" do
      settings = Settings.all()
      assert settings["ai_provider"] == "claude"
      assert settings["ai_model"] == "claude-sonnet-4-20250514"
      assert settings["git_provider"] == "gitlab"
      assert settings["git_token"] == ""
      assert settings["tracker_kind"] == "local"
    end
  end

  describe "get/1" do
    test "fetches individual setting" do
      assert Settings.get("ai_provider") == "claude"
    end

    test "returns nil for unknown key" do
      assert Settings.get("nonexistent") == nil
    end
  end

  describe "update/1" do
    test "updates known keys" do
      :ok = Settings.update(%{"ai_provider" => "openai", "ai_model" => "gpt-4o"})
      assert Settings.get("ai_provider") == "openai"
      assert Settings.get("ai_model") == "gpt-4o"
    end

    test "ignores unknown keys" do
      :ok = Settings.update(%{"bogus_key" => "nope", "ai_provider" => "gemini"})
      assert Settings.get("ai_provider") == "gemini"
      assert Settings.get("bogus_key") == nil
    end

    test "coerces atom keys to string" do
      :ok = Settings.update(%{ai_provider: "ollama"})
      # atom key "ai_provider" -> string "ai_provider"
      # The reduce uses to_string so it should still work
      assert Settings.get("ai_provider") == "ollama"
    end

    test "persists to disk" do
      :ok = Settings.update(%{"git_token" => "secret123"})
      assert File.exists?(@store_path)
      data = @store_path |> File.read!() |> Jason.decode!()
      assert data["git_token"] == "secret123"
    end
  end

  describe "reset/0" do
    test "restores defaults" do
      :ok = Settings.update(%{"ai_provider" => "openai", "git_token" => "tok"})
      assert Settings.get("ai_provider") == "openai"

      :ok = Settings.reset()
      assert Settings.get("ai_provider") == "claude"
      assert Settings.get("git_token") == ""
    end

    test "persists reset state" do
      :ok = Settings.update(%{"ai_model" => "custom-model"})
      :ok = Settings.reset()
      data = @store_path |> File.read!() |> Jason.decode!()
      assert data["ai_model"] == "claude-sonnet-4-20250514"
    end
  end

  describe "known_keys/0" do
    test "returns list of known setting keys" do
      keys = Settings.known_keys()
      assert "ai_provider" in keys
      assert "ai_model" in keys
      assert "git_provider" in keys
      assert "git_token" in keys
      assert "tracker_kind" in keys
      assert "auto_add_enabled" in keys
      assert "max_todo_parallel" in keys
      assert "segregate_by_project" in keys
    end
  end

  describe "board automation defaults" do
    test "auto_add_enabled defaults to false" do
      assert Settings.get("auto_add_enabled") == "false"
    end

    test "max_todo_parallel defaults to 3" do
      assert Settings.get("max_todo_parallel") == "3"
    end

    test "segregate_by_project defaults to false" do
      assert Settings.get("segregate_by_project") == "false"
    end

    test "updates board automation settings" do
      :ok =
        Settings.update(%{
          "auto_add_enabled" => "true",
          "max_todo_parallel" => "2",
          "segregate_by_project" => "true"
        })

      assert Settings.get("auto_add_enabled") == "true"
      assert Settings.get("max_todo_parallel") == "2"
      assert Settings.get("segregate_by_project") == "true"
    end
  end

  describe "persistence across restarts" do
    test "loads persisted settings on restart" do
      :ok = Settings.update(%{"ai_provider" => "gemini", "git_host" => "https://git.example.com"})
      stop_supervised!(Settings)

      start_supervised!({Settings, store_path: @store_path})
      assert Settings.get("ai_provider") == "gemini"
      assert Settings.get("git_host") == "https://git.example.com"
      # defaults still present for unmutated keys
      assert Settings.get("ai_model") == "claude-sonnet-4-20250514"
    end

    test "handles corrupt JSON gracefully" do
      File.write!(@store_path, "NOT VALID JSON {{{")
      stop_supervised!(Settings)

      start_supervised!({Settings, store_path: @store_path})
      # Falls back to defaults
      assert Settings.get("ai_provider") == "claude"
    end

    test "handles missing file gracefully" do
      File.rm(@store_path)
      stop_supervised!(Settings)

      start_supervised!({Settings, store_path: @store_path})
      assert Settings.get("ai_provider") == "claude"
    end
  end
end
