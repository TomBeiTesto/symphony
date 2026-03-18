defmodule SymphonyElixir.Integrations.KnowledgeBaseTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Integrations.KnowledgeBase

  setup do
    test_vault = Path.join(System.tmp_dir!(), "kb_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(test_vault)
    on_exit(fn -> File.rm_rf!(test_vault) end)

    base_config = %{
      "kb_type" => "local",
      "vault_path" => test_vault,
      "subfolder" => "symphony"
    }

    {:ok, vault: test_vault, config: base_config}
  end

  # ---------------------------------------------------------------------------
  # write_note
  # ---------------------------------------------------------------------------

  describe "write_note" do
    test "writes markdown file with YAML frontmatter", %{config: config, vault: vault} do
      context = %{
        "title" => "Domain Rules",
        "content" => "## Rule 1\nUsers must have an email.",
        "tags" => ["business-logic", "auth"],
        "source_issue" => "SYM-42",
        "product_name" => "my-product"
      }

      assert {:ok, %{path: path}} =
               KnowledgeBase.execute(Map.put(config, "action", "write_note"), context)

      assert File.exists?(path)
      content = File.read!(path)
      assert content =~ ~r/^---\n/
      assert content =~ "tags:"
      assert content =~ "business-logic"
      assert content =~ "source:"
      assert content =~ "SYM-42"
      assert content =~ "## Rule 1"

      # Verify it's under the correct product subfolder
      expected_dir = Path.join([vault, "symphony", "my-product"])
      assert String.starts_with?(Path.expand(path), Path.expand(expected_dir))
    end

    test "creates subfolder and product directory if missing", %{config: config, vault: vault} do
      context = %{
        "title" => "New Note",
        "content" => "Content here.",
        "product_name" => "new-product"
      }

      assert {:ok, %{path: _path}} =
               KnowledgeBase.execute(Map.put(config, "action", "write_note"), context)

      assert File.dir?(Path.join([vault, "symphony", "new-product"]))
    end

    test "sanitizes filename - strips special chars, preserves spaces", %{config: config} do
      context = %{
        "title" => "My Report: A <Test> File?",
        "content" => "body",
        "product_name" => "prod"
      }

      assert {:ok, %{path: path}} =
               KnowledgeBase.execute(Map.put(config, "action", "write_note"), context)

      filename = Path.basename(path)
      refute filename =~ ":"
      refute filename =~ "<"
      refute filename =~ ">"
      refute filename =~ "?"
      assert filename =~ "My Report"
    end

    test "rejects path traversal in title", %{config: config} do
      context = %{
        "title" => "../../etc/passwd",
        "content" => "malicious",
        "product_name" => "prod"
      }

      assert {:error, :path_traversal} =
               KnowledgeBase.execute(Map.put(config, "action", "write_note"), context)
    end

    test "rejects path traversal in product_name", %{config: config} do
      context = %{
        "title" => "safe-title",
        "content" => "ok",
        "product_name" => "../../../escape"
      }

      assert {:error, :path_traversal} =
               KnowledgeBase.execute(Map.put(config, "action", "write_note"), context)
    end

    test "overwrites existing note with same title", %{config: config} do
      context = %{
        "title" => "Overwrite Me",
        "content" => "version 1",
        "product_name" => "prod"
      }

      assert {:ok, %{path: path}} =
               KnowledgeBase.execute(Map.put(config, "action", "write_note"), context)

      assert File.read!(path) =~ "version 1"

      context2 = Map.put(context, "content", "version 2")

      assert {:ok, %{path: ^path}} =
               KnowledgeBase.execute(Map.put(config, "action", "write_note"), context2)

      assert File.read!(path) =~ "version 2"
      refute File.read!(path) =~ "version 1"
    end

    test "writes without product_name into subfolder root", %{config: config, vault: vault} do
      context = %{
        "title" => "Orphan Note",
        "content" => "no product"
      }

      assert {:ok, %{path: path}} =
               KnowledgeBase.execute(Map.put(config, "action", "write_note"), context)

      expected_dir = Path.join(vault, "symphony")
      assert String.starts_with?(Path.expand(path), Path.expand(expected_dir))
    end
  end

  # ---------------------------------------------------------------------------
  # read_note
  # ---------------------------------------------------------------------------

  describe "read_note" do
    test "reads file and splits frontmatter from content", %{config: config, vault: vault} do
      # Write a note with frontmatter manually
      dir = Path.join([vault, "symphony", "test-prod"])
      File.mkdir_p!(dir)
      note_path = Path.join(dir, "test-note.md")

      File.write!(note_path, """
      ---
      tags:
        - research
      source: SYM-1
      ---
      # My Research

      Some findings here.
      """)

      rel_path = Path.relative_to(note_path, vault)

      context = %{"note_path" => rel_path}

      assert {:ok, result} =
               KnowledgeBase.execute(Map.put(config, "action", "read_note"), context)

      assert result.frontmatter["source"] == "SYM-1"
      assert "research" in result.frontmatter["tags"]
      assert result.content =~ "# My Research"
      assert result.content =~ "Some findings here."
    end

    test "returns error for missing file", %{config: config} do
      context = %{"note_path" => "nonexistent/file.md"}

      assert {:error, :file_not_found} =
               KnowledgeBase.execute(Map.put(config, "action", "read_note"), context)
    end

    test "handles file without frontmatter gracefully", %{config: config, vault: vault} do
      dir = Path.join(vault, "symphony")
      File.mkdir_p!(dir)
      note_path = Path.join(dir, "no-frontmatter.md")
      File.write!(note_path, "# Just content\n\nNo frontmatter here.")

      rel_path = Path.relative_to(note_path, vault)
      context = %{"note_path" => rel_path}

      assert {:ok, result} =
               KnowledgeBase.execute(Map.put(config, "action", "read_note"), context)

      assert result.frontmatter == %{}
      assert result.content =~ "# Just content"
    end

    test "blocks path traversal in note_path", %{config: config} do
      context = %{"note_path" => "../../../etc/passwd"}

      assert {:error, :path_traversal} =
               KnowledgeBase.execute(Map.put(config, "action", "read_note"), context)
    end
  end

  # ---------------------------------------------------------------------------
  # search
  # ---------------------------------------------------------------------------

  describe "search" do
    setup %{vault: vault} do
      # Create several test notes
      dir = Path.join([vault, "symphony", "search-prod"])
      File.mkdir_p!(dir)

      File.write!(
        Path.join(dir, "domain-rules.md"),
        "---\ntags:\n  - business-logic\n---\n# Domain Rules\nBR-001: Users must verify email before login.\n"
      )

      File.write!(
        Path.join(dir, "workflows.md"),
        "---\ntags:\n  - workflow\n---\n# Workflows\nThe checkout flow requires payment validation.\n"
      )

      File.write!(Path.join(dir, "unrelated.md"), "# Unrelated\nNothing matching here at all.\n")

      :ok
    end

    test "finds notes by title match", %{config: config} do
      context = %{"query" => "Domain Rules"}

      assert {:ok, %{results: results}} =
               KnowledgeBase.execute(Map.put(config, "action", "search"), context)

      paths = Enum.map(results, & &1.path)
      assert Enum.any?(paths, &String.contains?(&1, "domain-rules"))
    end

    test "finds notes by content match", %{config: config} do
      context = %{"query" => "payment validation"}

      assert {:ok, %{results: results}} =
               KnowledgeBase.execute(Map.put(config, "action", "search"), context)

      paths = Enum.map(results, & &1.path)
      assert Enum.any?(paths, &String.contains?(&1, "workflows"))
    end

    test "returns empty list when no matches", %{config: config} do
      context = %{"query" => "xyzzy_absolutely_no_match"}

      assert {:ok, %{results: []}} =
               KnowledgeBase.execute(Map.put(config, "action", "search"), context)
    end

    test "caps results at 50", %{vault: vault, config: config} do
      # Create 60 matching files
      dir = Path.join([vault, "symphony", "many-notes"])
      File.mkdir_p!(dir)

      for i <- 1..60 do
        File.write!(Path.join(dir, "note-#{i}.md"), "matching keyword bananaphone")
      end

      context = %{"query" => "bananaphone"}

      assert {:ok, %{results: results}} =
               KnowledgeBase.execute(Map.put(config, "action", "search"), context)

      assert length(results) <= 50
    end

    test "results include path, title, and snippet", %{config: config} do
      context = %{"query" => "BR-001"}

      assert {:ok, %{results: [result | _]}} =
               KnowledgeBase.execute(Map.put(config, "action", "search"), context)

      assert Map.has_key?(result, :path)
      assert Map.has_key?(result, :title)
      assert Map.has_key?(result, :snippet)
      assert result.snippet =~ "BR-001"
    end
  end

  # ---------------------------------------------------------------------------
  # append_to_note
  # ---------------------------------------------------------------------------

  describe "append_to_note" do
    test "appends content with timestamp separator", %{config: config, vault: vault} do
      dir = Path.join([vault, "symphony", "append-prod"])
      File.mkdir_p!(dir)
      note_path = Path.join(dir, "existing.md")
      File.write!(note_path, "# Original\n\nOriginal content.")

      rel_path = Path.relative_to(note_path, vault)

      context = %{
        "note_path" => rel_path,
        "content" => "## New Section\n\nAppended content."
      }

      assert {:ok, %{path: _}} =
               KnowledgeBase.execute(Map.put(config, "action", "append_to_note"), context)

      updated = File.read!(note_path)
      assert updated =~ "# Original"
      assert updated =~ "Original content."
      assert updated =~ "---"
      assert updated =~ "Updated"
      assert updated =~ "## New Section"
      assert updated =~ "Appended content."
    end

    test "returns error for missing file", %{config: config} do
      context = %{
        "note_path" => "nonexistent/note.md",
        "content" => "cannot append"
      }

      assert {:error, :file_not_found} =
               KnowledgeBase.execute(Map.put(config, "action", "append_to_note"), context)
    end

    test "blocks path traversal", %{config: config} do
      context = %{
        "note_path" => "../../../etc/passwd",
        "content" => "malicious"
      }

      assert {:error, :path_traversal} =
               KnowledgeBase.execute(Map.put(config, "action", "append_to_note"), context)
    end
  end

  # ---------------------------------------------------------------------------
  # delete_note
  # ---------------------------------------------------------------------------

  describe "delete_note" do
    test "deletes an existing note", %{config: config, vault: vault} do
      dir = Path.join([vault, "symphony", "del-prod"])
      File.mkdir_p!(dir)
      note_path = Path.join(dir, "to-delete.md")
      File.write!(note_path, "# Delete me")

      rel_path = Path.relative_to(note_path, vault)
      context = %{"note_path" => rel_path}

      assert {:ok, %{deleted: true}} =
               KnowledgeBase.execute(Map.put(config, "action", "delete_note"), context)

      refute File.exists?(note_path)
    end

    test "returns error for missing file", %{config: config} do
      context = %{"note_path" => "nonexistent/file.md"}

      assert {:error, :file_not_found} =
               KnowledgeBase.execute(Map.put(config, "action", "delete_note"), context)
    end

    test "blocks path traversal", %{config: config} do
      context = %{"note_path" => "../../../etc/passwd"}

      assert {:error, :path_traversal} =
               KnowledgeBase.execute(Map.put(config, "action", "delete_note"), context)
    end
  end

  # ---------------------------------------------------------------------------
  # test_connection
  # ---------------------------------------------------------------------------

  describe "test_connection" do
    test "returns ok for valid directory", %{config: config} do
      assert {:ok, message} = KnowledgeBase.test_connection(config)
      assert is_binary(message)
    end

    test "returns error for missing directory" do
      config = %{
        "kb_type" => "local",
        "vault_path" => "/nonexistent/path/that/does/not/exist"
      }

      assert {:error, _} = KnowledgeBase.test_connection(config)
    end

    test "returns ok with warning if no .obsidian/ folder for obsidian type", %{vault: vault} do
      config = %{
        "kb_type" => "obsidian",
        "vault_path" => vault
      }

      # vault exists but has no .obsidian/ subfolder
      assert {:ok, message} = KnowledgeBase.test_connection(config)
      assert message =~ "warning" or message =~ "Warning" or message =~ "not an Obsidian"
    end

    test "returns ok without warning when .obsidian/ exists", %{vault: vault} do
      File.mkdir_p!(Path.join(vault, ".obsidian"))

      config = %{
        "kb_type" => "obsidian",
        "vault_path" => vault
      }

      assert {:ok, message} = KnowledgeBase.test_connection(config)
      refute message =~ "warning" or message =~ "Warning" or message =~ "not an Obsidian"
    end

    test "returns error for empty vault_path with obsidian type" do
      config = %{"kb_type" => "obsidian", "vault_path" => ""}

      assert {:error, _} = KnowledgeBase.test_connection(config)
    end

    test "local type with empty vault_path auto-creates default dir" do
      config = %{"kb_type" => "local", "vault_path" => ""}

      assert {:ok, message} = KnowledgeBase.test_connection(config)
      assert message =~ "Connected"
    end
  end

  # ---------------------------------------------------------------------------
  # backend dispatch
  # ---------------------------------------------------------------------------

  describe "resolve_base_path" do
    test "local backend uses vault_path as base", %{vault: vault} do
      config = %{"kb_type" => "local", "vault_path" => vault, "subfolder" => "symphony"}

      assert {:ok, base} = KnowledgeBase.resolve_base_path(config)
      assert base == vault
    end

    test "local backend falls back to default path when vault_path is empty" do
      config = %{"kb_type" => "local", "vault_path" => ""}

      assert {:ok, base} = KnowledgeBase.resolve_base_path(config)
      assert base == KnowledgeBase.default_local_path()
      assert File.dir?(base)
    end

    test "obsidian backend uses configured vault_path", %{vault: vault} do
      config = %{"kb_type" => "obsidian", "vault_path" => vault, "subfolder" => "symphony"}

      assert {:ok, base} = KnowledgeBase.resolve_base_path(config)
      assert base == vault
    end

    test "obsidian backend returns error when vault_path is empty" do
      config = %{"kb_type" => "obsidian", "vault_path" => ""}

      assert {:error, :no_vault_path} = KnowledgeBase.resolve_base_path(config)
    end

    test "confluence backend returns error for file operations" do
      config = %{
        "kb_type" => "confluence",
        "vault_path" => ""
      }

      assert {:error, :confluence_not_file_based} = KnowledgeBase.resolve_base_path(config)
    end
  end

  describe "default_local_path" do
    test "returns path under user home" do
      path = KnowledgeBase.default_local_path()
      assert String.contains?(path, ".symphony")
      assert String.contains?(path, "knowledge_base")
    end
  end

  # ---------------------------------------------------------------------------
  # obsidian-specific: wikilinks
  # ---------------------------------------------------------------------------

  describe "obsidian wikilinks" do
    test "obsidian backend adds wikilink source reference", %{vault: vault} do
      config = %{
        "kb_type" => "obsidian",
        "vault_path" => vault,
        "subfolder" => "symphony",
        "action" => "write_note"
      }

      context = %{
        "title" => "Wiki Test",
        "content" => "Some content.",
        "source_issue" => "SYM-99",
        "product_name" => "wiki-prod"
      }

      assert {:ok, %{path: path}} = KnowledgeBase.execute(config, context)
      content = File.read!(path)
      assert content =~ "[[SYM-99]]"
    end
  end

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  describe "build_frontmatter" do
    test "produces valid YAML frontmatter" do
      fm =
        KnowledgeBase.build_frontmatter(%{
          "tags" => ["research", "auth"],
          "source" => "SYM-1",
          "date" => "2026-03-18"
        })

      assert fm =~ "---\n"
      assert fm =~ "tags:"
      assert fm =~ "  - research"
      assert fm =~ "  - auth"
      assert fm =~ "source:"
      assert fm =~ "SYM-1"
      assert fm =~ "date:"
      assert fm =~ "2026-03-18"
      # Ends with closing ---
      assert fm =~ ~r/---\n$/
    end

    test "handles empty map" do
      fm = KnowledgeBase.build_frontmatter(%{})
      assert fm == "---\n---\n"
    end
  end

  describe "parse_frontmatter" do
    test "parses YAML frontmatter from markdown" do
      content = """
      ---
      tags:
        - test
      source: SYM-1
      ---
      # Body

      Content here.
      """

      {frontmatter, body} = KnowledgeBase.parse_frontmatter(content)
      assert frontmatter["source"] == "SYM-1"
      assert "test" in frontmatter["tags"]
      assert body =~ "# Body"
    end

    test "returns empty map for content without frontmatter" do
      {frontmatter, body} = KnowledgeBase.parse_frontmatter("# Just markdown\n\nNo frontmatter.")
      assert frontmatter == %{}
      assert body =~ "# Just markdown"
    end
  end

  describe "sanitize_filename" do
    test "removes invalid characters" do
      assert KnowledgeBase.sanitize_filename("My File: A <Test>?") == "My File A Test"
    end

    test "preserves spaces and hyphens" do
      assert KnowledgeBase.sanitize_filename("my-file name") == "my-file name"
    end

    test "collapses multiple spaces" do
      assert KnowledgeBase.sanitize_filename("too   many   spaces") == "too many spaces"
    end

    test "trims leading/trailing whitespace" do
      assert KnowledgeBase.sanitize_filename("  padded  ") == "padded"
    end
  end
end
