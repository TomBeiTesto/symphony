defmodule SymphonyElixir.Integrations.KnowledgeBase do
  @moduledoc """
  Unified knowledge base interface with three backends: local, obsidian, and confluence.

  Local and obsidian backends use filesystem I/O (markdown files with YAML frontmatter).
  Confluence backend delegates to `SymphonyElixir.Integrations.Confluence`.

  Actions: write_note, read_note, search, search_by_tags, search_by_metadata, append_to_note,
  merge_note, delete_note, list_versions, read_version, restore_version.
  """

  require Logger

  alias SymphonyElixir.{Integrations.KBIndex, PathUtils}

  @max_search_results 50
  @max_versions 50

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Execute a knowledge base action based on config.

  Config fields:
  - kb_type: "local" | "obsidian" | "confluence"
  - vault_path: filesystem path (for local/obsidian)
  - subfolder: relative path within vault (default "symphony")
  - action: "write_note" | "read_note" | "search" | "append_to_note" | "merge_note" | "delete_note"
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(config, context) do
    kb_type = Map.get(config, "kb_type", "local")
    action = Map.get(config, "action", "write_note")

    if kb_type == "confluence" do
      execute_confluence(action, config, context)
    else
      case action do
        "write_note" -> write_note(config, context)
        "read_note" -> read_note(config, context)
        "search" -> search(config, context)
        "search_by_tags" -> search_by_tags(config, context)
        "search_by_metadata" -> search_by_metadata(config, context)
        "append_to_note" -> append_to_note(config, context)
        "merge_note" -> merge_note(config, context)
        "delete_note" -> delete_note(config, context)
        "list_versions" -> list_versions(config, context)
        "read_version" -> read_version(config, context)
        "restore_version" -> restore_version(config, context)
        _ -> {:error, "Unknown KB action: #{action}"}
      end
    end
  end

  @doc "Test that the KB backend is reachable."
  @spec test_connection(map()) :: {:ok, String.t()} | {:error, String.t()}
  def test_connection(config) do
    kb_type = Map.get(config, "kb_type", "local")

    case kb_type do
      "confluence" ->
        SymphonyElixir.Integrations.Confluence.test_connection(config)

      type when type in ["local", "obsidian"] ->
        vault_path = Map.get(config, "vault_path", "")

        resolved_path =
          if vault_path == "" and type == "local", do: default_local_path(), else: vault_path

        cond do
          resolved_path == "" ->
            {:error, "No vault path configured"}

          not File.dir?(resolved_path) ->
            # For local type with default path, auto-create the directory
            if type == "local" and vault_path == "" do
              File.mkdir_p!(resolved_path)
              {:ok, "Connected to #{resolved_path} (auto-created)"}
            else
              {:error, "Directory does not exist: #{resolved_path}"}
            end

          type == "obsidian" and not File.dir?(Path.join(resolved_path, ".obsidian")) ->
            {:ok,
             "Connected to #{resolved_path} (Warning: not an Obsidian vault — no .obsidian/ folder found)"}

          true ->
            {:ok, "Connected to #{resolved_path}"}
        end

      _ ->
        {:error, "Unknown KB type: #{kb_type}"}
    end
  end

  @doc "Resolve the filesystem base path for local/obsidian backends."
  @spec resolve_base_path(map()) :: {:ok, String.t()} | {:error, atom()}
  def resolve_base_path(config) do
    kb_type = Map.get(config, "kb_type", "local")

    case kb_type do
      "confluence" ->
        {:error, :confluence_not_file_based}

      type when type in ["local", "obsidian"] ->
        vault_path = Map.get(config, "vault_path", "")

        cond do
          vault_path != "" ->
            {:ok, vault_path}

          type == "local" ->
            path = default_local_path()
            File.mkdir_p!(path)
            {:ok, path}

          true ->
            {:error, :no_vault_path}
        end

      _ ->
        {:error, :unknown_kb_type}
    end
  end

  # ---------------------------------------------------------------------------
  # Confluence backend delegation
  # ---------------------------------------------------------------------------

  defp execute_confluence(action, config, context) do
    alias SymphonyElixir.Integrations.Confluence

    case action do
      "write_note" ->
        title = Map.get(context, "title", "Untitled")
        content = Map.get(context, "content", "")
        tags = Map.get(context, "tags", [])
        tag_line = if tags != [], do: "Tags: #{Enum.join(tags, ", ")}\n\n", else: ""

        confluence_config =
          Map.merge(config, %{
            "action" => "create_page",
            "title" => title,
            "content" => tag_line <> content
          })

        case Confluence.execute(confluence_config, context) do
          {:ok, result} -> {:ok, %{path: result[:page_id] || result["page_id"], title: title}}
          error -> error
        end

      "read_note" ->
        page_id = Map.get(context, "note_path", "") |> Path.basename(".md")

        confluence_config =
          Map.merge(config, %{
            "action" => "get_page",
            "page_id" => page_id
          })

        case Confluence.execute(confluence_config, context) do
          {:ok, result} ->
            {:ok,
             %{
               frontmatter: %{},
               content: result[:content] || result["content"] || "",
               path: page_id
             }}

          error ->
            error
        end

      "append_to_note" ->
        page_id = Map.get(context, "note_path", "") |> Path.basename(".md")
        new_content = Map.get(context, "content", "")
        timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.to_string()

        confluence_config =
          Map.merge(config, %{
            "action" => "update_page",
            "page_id" => page_id,
            "append_content" => "\n\n---\n*Updated #{timestamp}*\n\n#{new_content}"
          })

        case Confluence.execute(confluence_config, context) do
          {:ok, _} -> {:ok, %{path: page_id}}
          error -> error
        end

      "search" ->
        {:error, "Confluence search not yet implemented — use Confluence UI directly"}

      "search_by_tags" ->
        {:error, "Confluence tag search not yet implemented — use Confluence UI directly"}

      "search_by_metadata" ->
        {:error, "Confluence metadata search not yet implemented — use Confluence UI directly"}

      unsupported
      when unsupported in ~w(delete_note list_versions read_version restore_version) ->
        {:error, "Action '#{unsupported}' is not supported for Confluence backend"}

      _ ->
        {:error, "Unknown KB action: #{action}"}
    end
  end

  # ---------------------------------------------------------------------------
  # Frontmatter helpers (public for testing)
  # ---------------------------------------------------------------------------

  @doc "Build YAML frontmatter string from a map."
  @spec build_frontmatter(map()) :: String.t()
  def build_frontmatter(attrs) when map_size(attrs) == 0, do: "---\n---\n"

  def build_frontmatter(attrs) do
    lines =
      attrs
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.flat_map(fn {key, value} ->
        case value do
          list when is_list(list) ->
            ["#{key}:"] ++ Enum.map(list, fn item -> "  - #{item}" end)

          _ ->
            ["#{key}: #{quote_value(value)}"]
        end
      end)

    "---\n" <> Enum.join(lines, "\n") <> "\n---\n"
  end

  @doc "Parse YAML frontmatter from markdown content. Returns {frontmatter_map, body}."
  @spec parse_frontmatter(String.t()) :: {map(), String.t()}
  def parse_frontmatter(content) do
    case Regex.run(~r/\A---\n(.*?\n)---\n(.*)\z/s, content) do
      [_, yaml_block, body] ->
        frontmatter = parse_simple_yaml(yaml_block)
        {frontmatter, body}

      _ ->
        {%{}, content}
    end
  end

  @doc "Sanitize a string for use as a filename."
  @spec sanitize_filename(String.t()) :: String.t()
  def sanitize_filename(name) do
    name
    |> String.replace(~r/[<>:"\/\\|?*]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------

  defp write_note(config, context) do
    with {:ok, base_path} <- resolve_base_path(config) do
      subfolder = Map.get(config, "subfolder", "symphony")
      kb_type = Map.get(config, "kb_type", "local")
      product_name = Map.get(context, "product_name")
      title = Map.get(context, "title", "Untitled")
      content = Map.get(context, "content", "")
      tags = Map.get(context, "tags", [])
      source_issue = Map.get(context, "source_issue")

      # Reject path traversal in raw inputs before sanitization
      if contains_traversal?(title) or contains_traversal?(product_name) do
        {:error, :path_traversal}
      else
        # Build target directory
        dir_parts = [base_path, subfolder] ++ if(product_name, do: [product_name], else: [])
        target_dir = Path.join(dir_parts)
        filename = sanitize_filename(title) <> ".md"
        target_path = Path.join(target_dir, filename)

        if path_traversal?(target_path, base_path) do
          {:error, :path_traversal}
        else
          # Build frontmatter
          fm_attrs =
            %{}
            |> maybe_put("tags", tags, tags != [])
            |> maybe_put("source", source_issue, source_issue != nil)
            |> maybe_put("date", Date.utc_today() |> Date.to_iso8601(), true)
            |> maybe_put("product", product_name, product_name != nil)

          frontmatter = build_frontmatter(fm_attrs)

          # Build body — add wikilink for obsidian
          body =
            if kb_type == "obsidian" and source_issue do
              "> Source: [[#{source_issue}]]\n\n#{content}"
            else
              content
            end

          full_content = frontmatter <> "\n" <> body

          File.mkdir_p!(target_dir)

          # Archive previous version before overwriting
          if File.exists?(target_path) do
            archive_version(target_dir, filename, target_path)
          end

          File.write!(target_path, full_content)

          # Invalidate index — key must match search_dir (base_path + subfolder)
          search_dir = Path.join(base_path, subfolder)
          rel = Path.relative_to(target_path, search_dir)
          KBIndex.invalidate(search_dir, rel)

          {:ok, %{path: target_path}}
        end
      end
    end
  end

  defp read_note(config, context) do
    with {:ok, base_path} <- resolve_base_path(config) do
      note_path = Map.get(context, "note_path", "")
      full_path = Path.join(base_path, note_path)

      cond do
        path_traversal?(full_path, base_path) ->
          {:error, :path_traversal}

        not File.exists?(full_path) ->
          {:error, :file_not_found}

        true ->
          raw = File.read!(full_path)
          {frontmatter, body} = parse_frontmatter(raw)
          {:ok, %{frontmatter: frontmatter, content: body, path: full_path}}
      end
    end
  end

  defp search(config, context) do
    with {:ok, base_path} <- resolve_base_path(config) do
      subfolder = Map.get(config, "subfolder", "symphony")
      query = Map.get(context, "query", "")
      search_dir = Path.join(base_path, subfolder)

      if not File.dir?(search_dir) do
        {:ok, %{results: []}}
      else
        # Use ETS-backed index for fast search
        results = KBIndex.search(search_dir, query, @max_search_results)
        {:ok, %{results: results}}
      end
    end
  end

  defp search_by_tags(config, context) do
    with {:ok, base_path} <- resolve_base_path(config) do
      subfolder = Map.get(config, "subfolder", "symphony")
      tags = Map.get(context, "tags", [])
      limit = Map.get(context, "limit", @max_search_results)
      search_dir = Path.join(base_path, subfolder)

      if not File.dir?(search_dir) do
        {:ok, %{results: []}}
      else
        results = KBIndex.search_by_tags(search_dir, tags, limit)
        {:ok, %{results: results}}
      end
    end
  end

  defp search_by_metadata(config, context) do
    with {:ok, base_path} <- resolve_base_path(config) do
      subfolder = Map.get(config, "subfolder", "symphony")
      filters = Map.get(context, "filters", %{})
      limit = Map.get(context, "limit", @max_search_results)
      search_dir = Path.join(base_path, subfolder)

      if not File.dir?(search_dir) do
        {:ok, %{results: []}}
      else
        results = KBIndex.search_by_metadata(search_dir, filters, limit)
        {:ok, %{results: results}}
      end
    end
  end

  defp append_to_note(config, context) do
    with {:ok, base_path} <- resolve_base_path(config) do
      subfolder = Map.get(config, "subfolder", "symphony")
      note_path = Map.get(context, "note_path", "")
      new_content = Map.get(context, "content", "")
      full_path = Path.join(base_path, note_path)

      cond do
        path_traversal?(full_path, base_path) ->
          {:error, :path_traversal}

        not File.exists?(full_path) ->
          {:error, :file_not_found}

        true ->
          existing = File.read!(full_path)
          timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.to_string()
          separator = "\n\n---\n*Updated #{timestamp}*\n\n"
          File.write!(full_path, existing <> separator <> new_content)

          # Invalidate index — key must match search_dir (base_path + subfolder)
          search_dir = Path.join(base_path, subfolder)
          rel = Path.relative_to(full_path, search_dir)
          KBIndex.invalidate(search_dir, rel)

          {:ok, %{path: full_path}}
      end
    end
  end

  # merge_note: Intelligently merge new information into an existing KB note using the LLM.
  # If the note doesn't exist yet, falls back to write_note.
  # Context fields:
  #   - title: note title (used to find the file)
  #   - content: new information to merge in
  #   - product_name: product subfolder
  #   - merge_context: optional description of what changed (helps the LLM)
  defp merge_note(config, context) do
    with {:ok, base_path} <- resolve_base_path(config) do
      subfolder = Map.get(config, "subfolder", "symphony")
      product_name = Map.get(context, "product_name")
      title = Map.get(context, "title", "Untitled")
      new_content = Map.get(context, "content", "")
      merge_context = Map.get(context, "merge_context", "")

      if contains_traversal?(title) or contains_traversal?(product_name) do
        {:error, :path_traversal}
      else
        dir_parts = [base_path, subfolder] ++ if(product_name, do: [product_name], else: [])
        target_dir = Path.join(dir_parts)
        filename = sanitize_filename(title) <> ".md"
        target_path = Path.join(target_dir, filename)

        if path_traversal?(target_path, base_path) do
          {:error, :path_traversal}
        else
          if File.exists?(target_path) do
            existing_raw = File.read!(target_path)
            {_fm, existing_body} = parse_frontmatter(existing_raw)

            do_llm_merge(
              existing_body,
              new_content,
              title,
              merge_context,
              config,
              context,
              target_path
            )
          else
            # No existing note — just write a new one
            Logger.info("KB merge_note: no existing '#{title}', creating new note")
            write_note(config, context)
          end
        end
      end
    end
  end

  defp do_llm_merge(
         existing_body,
         new_content,
         title,
         merge_context,
         config,
         context,
         target_path
       ) do
    context_hint =
      if merge_context != "",
        do: "\n\nContext about the changes: #{merge_context}",
        else: ""

    prompt = """
    You are updating a knowledge base note. The existing note contains the current understanding
    of a topic. New information has been produced (from a pipeline run) that may update, extend,
    or correct parts of this knowledge.

    Your task: produce an UPDATED version of the note that integrates the new information.

    Rules:
    - Preserve the existing note's structure and sections
    - Update facts that have changed (don't keep outdated information alongside new)
    - Add new sections or bullet points for genuinely new information
    - Remove information that the new content explicitly supersedes
    - Do NOT add a changelog or "updated on" section — just produce the clean, merged note
    - Do NOT wrap the output in markdown code fences — output the note content directly
    - Keep the same style and tone as the existing note
    - If the new information is not relevant to this note's topic, return the existing note unchanged
    #{context_hint}

    ## Existing Note: "#{title}"

    #{existing_body}

    ## New Information

    #{new_content}

    ## Your Output

    Return ONLY the updated note content (no frontmatter, no code fences).
    """

    case SymphonyElixir.LLM.call(prompt,
           system: "You are a knowledge base editor. Be precise and factual."
         ) do
      {:ok, merged_body} ->
        # Rebuild the note with updated frontmatter
        tags = Map.get(context, "tags", [])
        product_name = Map.get(context, "product_name")
        source_issue = Map.get(context, "source_issue")

        fm_attrs =
          %{}
          |> maybe_put("tags", tags, tags != [])
          |> maybe_put("source", source_issue, source_issue != nil)
          |> maybe_put("date", Date.utc_today() |> Date.to_iso8601(), true)
          |> maybe_put("product", product_name, product_name != nil)

        frontmatter = build_frontmatter(fm_attrs)

        kb_type = Map.get(config, "kb_type", "local")

        body =
          if kb_type == "obsidian" and source_issue do
            "> Source: [[#{source_issue}]]\n\n#{merged_body}"
          else
            merged_body
          end

        full_content = frontmatter <> "\n" <> body

        # Archive previous version
        dir = Path.dirname(target_path)
        filename = Path.basename(target_path)
        archive_version(dir, filename, target_path)

        File.write!(target_path, full_content)

        # Invalidate index
        subfolder = Map.get(config, "subfolder", "symphony")
        base_path = elem(resolve_base_path(config), 1)
        search_dir = Path.join(base_path, subfolder)
        rel = Path.relative_to(target_path, search_dir)
        KBIndex.invalidate(search_dir, rel)

        Logger.info("KB merge_note: merged and wrote #{target_path}")
        {:ok, %{path: target_path, merged: true}}

      {:error, reason} ->
        Logger.warning(
          "KB merge_note: LLM merge failed (#{inspect(reason)}), falling back to write_note"
        )

        write_note(config, context)
    end
  end

  defp delete_note(config, context) do
    with {:ok, base_path} <- resolve_base_path(config) do
      subfolder = Map.get(config, "subfolder", "symphony")
      note_path = Map.get(context, "note_path", "")
      full_path = Path.join(base_path, note_path)

      cond do
        path_traversal?(full_path, base_path) ->
          {:error, :path_traversal}

        not File.exists?(full_path) ->
          {:error, :file_not_found}

        true ->
          File.rm!(full_path)

          # Invalidate index — key must match search_dir (base_path + subfolder)
          search_dir = Path.join(base_path, subfolder)
          rel = Path.relative_to(full_path, search_dir)
          KBIndex.invalidate(search_dir, rel)

          {:ok, %{path: full_path, deleted: true}}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Versioning
  # ---------------------------------------------------------------------------

  defp list_versions(config, context) do
    with {:ok, base_path} <- resolve_base_path(config) do
      note_path = Map.get(context, "note_path", "")
      full_path = Path.join(base_path, note_path)

      if path_traversal?(full_path, base_path) do
        {:error, :path_traversal}
      else
        dir = Path.dirname(full_path)
        filename = Path.basename(full_path)
        versions_dir = Path.join(dir, ".versions")

        # Version files are named: {basename_without_ext}.{timestamp}.md
        base_name = Path.basename(filename, ".md")

        versions =
          if File.dir?(versions_dir) do
            wildcard = Path.join(versions_dir, "#{base_name}.*.md") |> String.replace("\\", "/")

            Path.wildcard(wildcard)
            |> Enum.map(fn vpath ->
              vname = Path.basename(vpath, ".md")
              # Extract timestamp from "basename.20260318T143022" pattern
              timestamp = String.replace_prefix(vname, "#{base_name}.", "")
              stat = File.stat!(vpath)

              %{
                path: Path.relative_to(vpath, base_path),
                timestamp: timestamp,
                size: stat.size,
                modified: NaiveDateTime.from_erl!(stat.mtime)
              }
            end)
            |> Enum.sort_by(& &1.timestamp, :desc)
            |> Enum.take(@max_versions)
          else
            []
          end

        {:ok, %{versions: versions, note_path: note_path}}
      end
    end
  end

  defp read_version(config, context) do
    with {:ok, base_path} <- resolve_base_path(config) do
      version_path = Map.get(context, "version_path", "")
      full_path = Path.join(base_path, version_path)

      cond do
        path_traversal?(full_path, base_path) ->
          {:error, :path_traversal}

        not File.exists?(full_path) ->
          {:error, :file_not_found}

        true ->
          raw = File.read!(full_path)
          {frontmatter, body} = parse_frontmatter(raw)
          {:ok, %{frontmatter: frontmatter, content: body, path: full_path}}
      end
    end
  end

  defp restore_version(config, context) do
    with {:ok, base_path} <- resolve_base_path(config) do
      subfolder = Map.get(config, "subfolder", "symphony")
      version_path = Map.get(context, "version_path", "")
      note_path = Map.get(context, "note_path", "")
      version_full = Path.join(base_path, version_path)
      note_full = Path.join(base_path, note_path)

      cond do
        path_traversal?(version_full, base_path) or path_traversal?(note_full, base_path) ->
          {:error, :path_traversal}

        not File.exists?(version_full) ->
          {:error, :file_not_found}

        true ->
          # Archive the current note before restoring
          if File.exists?(note_full) do
            dir = Path.dirname(note_full)
            filename = Path.basename(note_full)
            archive_version(dir, filename, note_full)
          end

          # Copy version content to the main note path
          content = File.read!(version_full)
          File.write!(note_full, content)

          # Invalidate index — key must match search_dir (base_path + subfolder)
          search_dir = Path.join(base_path, subfolder)
          rel = Path.relative_to(note_full, search_dir)
          KBIndex.invalidate(search_dir, rel)

          {:ok, %{path: note_full, restored_from: version_path}}
      end
    end
  end

  defp archive_version(dir, filename, source_path) do
    versions_dir = Path.join(dir, ".versions")
    File.mkdir_p!(versions_dir)

    base_name = Path.basename(filename, ".md")

    timestamp =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.to_iso8601()
      |> String.replace(~r/[:\.]/, "")
      |> String.slice(0, 15)

    version_filename = "#{base_name}.#{timestamp}.md"
    version_path = Path.join(versions_dir, version_filename)

    File.cp!(source_path, version_path)
    version_path
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @doc false
  def default_local_path do
    Path.join([System.user_home!(), ".symphony", "knowledge_base"])
  end

  defp contains_traversal?(nil), do: false

  defp contains_traversal?(value) do
    String.contains?(value, "..") or String.contains?(value, "~")
  end

  defp path_traversal?(target, base) do
    expanded_target = PathUtils.normalize_path(target)
    expanded_base = PathUtils.normalize_path(base)
    not String.starts_with?(expanded_target, expanded_base)
  end

  defp quote_value(value) when is_binary(value) do
    if String.contains?(value, ":") or String.contains?(value, "#") do
      "\"#{value}\""
    else
      "\"#{value}\""
    end
  end

  defp quote_value(value), do: to_string(value)

  defp maybe_put(map, _key, _value, false), do: map
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)

  # Simple YAML parser for frontmatter (handles flat key-value + list items)
  defp parse_simple_yaml(yaml_block) do
    SymphonyElixir.YamlParser.parse(yaml_block)
  end
end
