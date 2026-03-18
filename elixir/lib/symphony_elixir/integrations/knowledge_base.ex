defmodule SymphonyElixir.Integrations.KnowledgeBase do
  @moduledoc """
  Unified knowledge base interface with three backends: local, obsidian, and confluence.

  Local and obsidian backends use filesystem I/O (markdown files with YAML frontmatter).
  Confluence backend delegates to `SymphonyElixir.Integrations.Confluence`.

  Actions: write_note, read_note, search, append_to_note, delete_note.
  """

  require Logger

  @max_search_results 50

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Execute a knowledge base action based on config.

  Config fields:
  - kb_type: "local" | "obsidian" | "confluence"
  - vault_path: filesystem path (for local/obsidian)
  - subfolder: relative path within vault (default "symphony")
  - action: "write_note" | "read_note" | "search" | "append_to_note" | "delete_note"
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(config, context) do
    action = Map.get(config, "action", "write_note")

    case action do
      "write_note" -> write_note(config, context)
      "read_note" -> read_note(config, context)
      "search" -> search(config, context)
      "append_to_note" -> append_to_note(config, context)
      "delete_note" -> delete_note(config, context)
      _ -> {:error, "Unknown KB action: #{action}"}
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
          File.write!(target_path, full_content)

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
        query_lower = String.downcase(query)

        # Normalize to forward slashes for Path.wildcard on Windows
        wildcard_pattern =
          Path.join(search_dir, "**/*.md") |> String.replace("\\", "/")

        results =
          Path.wildcard(wildcard_pattern)
          |> Enum.filter(fn path ->
            filename_lower = path |> Path.basename(".md") |> String.downcase()
            title_match = String.contains?(filename_lower, query_lower)

            content_match =
              if title_match do
                true
              else
                case File.read(path) do
                  {:ok, content} -> String.contains?(String.downcase(content), query_lower)
                  _ -> false
                end
              end

            title_match or content_match
          end)
          |> Enum.take(@max_search_results)
          |> Enum.map(fn path ->
            title = Path.basename(path, ".md")
            snippet = extract_snippet(path, query_lower)
            rel_path = Path.relative_to(path, base_path)
            %{path: rel_path, title: title, snippet: snippet}
          end)

        {:ok, %{results: results}}
      end
    end
  end

  defp append_to_note(config, context) do
    with {:ok, base_path} <- resolve_base_path(config) do
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
          {:ok, %{path: full_path}}
      end
    end
  end

  defp delete_note(config, context) do
    with {:ok, base_path} <- resolve_base_path(config) do
      note_path = Map.get(context, "note_path", "")
      full_path = Path.join(base_path, note_path)

      cond do
        path_traversal?(full_path, base_path) ->
          {:error, :path_traversal}

        not File.exists?(full_path) ->
          {:error, :file_not_found}

        true ->
          File.rm!(full_path)
          {:ok, %{path: full_path, deleted: true}}
      end
    end
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
    expanded_target = target |> Path.expand() |> normalize_path()
    expanded_base = base |> Path.expand() |> normalize_path()
    not String.starts_with?(expanded_target, expanded_base)
  end

  defp normalize_path(path) do
    path
    |> String.replace("\\", "/")
    |> String.downcase()
  end

  defp extract_snippet(path, query_lower) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.find(fn line ->
          String.contains?(String.downcase(line), query_lower)
        end)
        |> case do
          nil -> ""
          line -> String.trim(line) |> String.slice(0, 200)
        end

      _ ->
        ""
    end
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
    yaml_block
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> parse_yaml_lines(%{}, nil)
  end

  defp parse_yaml_lines([], acc, _current_list_key), do: acc

  defp parse_yaml_lines([line | rest], acc, current_list_key) do
    trimmed = String.trim(line)

    cond do
      # List item: "  - value"
      String.starts_with?(trimmed, "- ") and current_list_key != nil ->
        value = String.trim_leading(trimmed, "- ") |> String.trim()
        existing = Map.get(acc, current_list_key, [])

        parse_yaml_lines(
          rest,
          Map.put(acc, current_list_key, existing ++ [value]),
          current_list_key
        )

      # Key with empty value (list follows): "key:"
      String.ends_with?(trimmed, ":") ->
        key = String.trim_trailing(trimmed, ":")
        parse_yaml_lines(rest, acc, key)

      # Key-value pair: "key: value"
      String.contains?(trimmed, ": ") ->
        [key | value_parts] = String.split(trimmed, ": ", parts: 2)
        value = Enum.join(value_parts, ": ") |> String.trim() |> unquote_value()
        parse_yaml_lines(rest, Map.put(acc, key, value), nil)

      true ->
        parse_yaml_lines(rest, acc, current_list_key)
    end
  end

  defp unquote_value(value) do
    case value do
      "\"" <> rest -> String.trim_trailing(rest, "\"")
      "'" <> rest -> String.trim_trailing(rest, "'")
      other -> other
    end
  end
end
