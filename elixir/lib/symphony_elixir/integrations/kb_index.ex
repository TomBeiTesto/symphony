defmodule SymphonyElixir.Integrations.KBIndex do
  @moduledoc """
  In-memory search index for the Knowledge Base.

  Maintains an ETS-backed index of note metadata (path, title, tags, date,
  author, content preview) to avoid linear filesystem scans on every search.
  Rebuilds automatically when the vault directory changes.

  Used by KnowledgeBase.search/2 and search_by_tags/2.
  """

  use GenServer

  require Logger

  @table :kb_search_index
  @rebuild_interval_ms 60_000
  @max_content_preview 500

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Search the index by text query (title + content). Returns up to `limit` results."
  @spec search(String.t(), String.t(), pos_integer()) :: [map()]
  def search(vault_path, query, limit \\ 50) do
    GenServer.call(__MODULE__, {:search, vault_path, query, limit})
  end

  @doc "Search by frontmatter tags. Returns notes that have ALL specified tags."
  @spec search_by_tags(String.t(), [String.t()], pos_integer()) :: [map()]
  def search_by_tags(vault_path, tags, limit \\ 50) do
    GenServer.call(__MODULE__, {:search_by_tags, vault_path, tags, limit})
  end

  @doc "Search by metadata fields (date range, author, arbitrary frontmatter keys)."
  @spec search_by_metadata(String.t(), map(), pos_integer()) :: [map()]
  def search_by_metadata(vault_path, filters, limit \\ 50) do
    GenServer.call(__MODULE__, {:search_by_metadata, vault_path, filters, limit})
  end

  @doc "Invalidate a single note (after write/delete)."
  def invalidate(vault_path, note_path) do
    GenServer.cast(__MODULE__, {:invalidate, vault_path, note_path})
  end

  # --- Server ---

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{indexed_vaults: %{}}}
  end

  @impl true
  def handle_call({:search, vault_path, query, limit}, _from, state) do
    state = maybe_index(state, vault_path)
    results = do_text_search(vault_path, query, limit)
    {:reply, results, state}
  end

  @impl true
  def handle_call({:search_by_tags, vault_path, tags, limit}, _from, state) do
    state = maybe_index(state, vault_path)
    results = do_tag_search(vault_path, tags, limit)
    {:reply, results, state}
  end

  @impl true
  def handle_call({:search_by_metadata, vault_path, filters, limit}, _from, state) do
    state = maybe_index(state, vault_path)
    results = do_metadata_search(vault_path, filters, limit)
    {:reply, results, state}
  end

  @impl true
  def handle_cast({:invalidate, vault_path, note_path}, state) do
    full_path = Path.join(vault_path, note_path)

    if File.exists?(full_path) do
      entry = index_single_file(vault_path, full_path)
      :ets.insert(@table, {{vault_path, note_path}, entry})
    else
      :ets.delete(@table, {vault_path, note_path})
    end

    {:noreply, state}
  end

  # --- Indexing ---

  defp maybe_index(state, vault_path) do
    last_indexed = Map.get(state.indexed_vaults, vault_path)
    now = System.monotonic_time(:millisecond)

    if is_nil(last_indexed) or now - last_indexed > @rebuild_interval_ms do
      index_vault(state, vault_path)
    else
      state
    end
  end

  defp index_vault(state, vault_path) do
    if File.dir?(vault_path) do
      wildcard = Path.join(vault_path, "**/*.md") |> String.replace("\\", "/")

      files = Path.wildcard(wildcard)

      # Remove stale entries for this vault
      :ets.match_delete(@table, {{vault_path, :_}, :_})

      # Index all files
      Enum.each(files, fn file_path ->
        # Skip .versions directories
        unless String.contains?(file_path, ".versions") do
          rel_path = Path.relative_to(file_path, vault_path)
          entry = index_single_file(vault_path, file_path)
          :ets.insert(@table, {{vault_path, rel_path}, entry})
        end
      end)

      Logger.debug("KBIndex: indexed #{length(files)} files in #{vault_path}")
    end

    now = System.monotonic_time(:millisecond)
    %{state | indexed_vaults: Map.put(state.indexed_vaults, vault_path, now)}
  end

  defp index_single_file(vault_path, file_path) do
    rel_path = Path.relative_to(file_path, vault_path)
    title = Path.basename(file_path, ".md")

    case File.read(file_path) do
      {:ok, content} ->
        {frontmatter, body} = split_frontmatter(content)
        metadata = parse_frontmatter_map(frontmatter)

        tags =
          case Map.get(metadata, "tags") do
            list when is_list(list) -> list
            str when is_binary(str) -> String.split(str, ",") |> Enum.map(&String.trim/1)
            _ -> []
          end

        %{
          path: rel_path,
          title: title,
          tags: tags,
          date: Map.get(metadata, "date"),
          author: Map.get(metadata, "author"),
          source: Map.get(metadata, "source"),
          product: Map.get(metadata, "product"),
          metadata: metadata,
          content_preview: String.slice(body, 0, @max_content_preview),
          content_lower: String.downcase(body),
          title_lower: String.downcase(title),
          mtime: file_mtime(file_path)
        }

      _ ->
        %{
          path: rel_path,
          title: title,
          tags: [],
          date: nil,
          author: nil,
          source: nil,
          product: nil,
          metadata: %{},
          content_preview: "",
          content_lower: "",
          title_lower: String.downcase(title),
          mtime: nil
        }
    end
  end

  # --- Search implementations ---

  defp do_text_search(vault_path, query, limit) do
    query_lower = String.downcase(query)
    query_terms = String.split(query_lower, ~r/\s+/, trim: true)

    all_entries(vault_path)
    |> Enum.filter(fn entry ->
      Enum.all?(query_terms, fn term ->
        String.contains?(entry.title_lower, term) or
          String.contains?(entry.content_lower, term) or
          Enum.any?(entry.tags, &String.contains?(String.downcase(&1), term))
      end)
    end)
    |> Enum.sort_by(fn entry ->
      # Rank: title matches first, then tag matches, then content
      title_match = if String.contains?(entry.title_lower, query_lower), do: 0, else: 1

      tag_match =
        if Enum.any?(entry.tags, &String.contains?(String.downcase(&1), query_lower)),
          do: 0,
          else: 1

      {title_match, tag_match, entry.path}
    end)
    |> Enum.take(limit)
    |> Enum.map(&entry_to_result/1)
  end

  defp do_tag_search(vault_path, tags, limit) do
    tags_lower = Enum.map(tags, &String.downcase/1)

    all_entries(vault_path)
    |> Enum.filter(fn entry ->
      entry_tags_lower = Enum.map(entry.tags, &String.downcase/1)

      Enum.all?(tags_lower, fn tag ->
        Enum.any?(entry_tags_lower, &String.contains?(&1, tag))
      end)
    end)
    |> Enum.take(limit)
    |> Enum.map(&entry_to_result/1)
  end

  defp do_metadata_search(vault_path, filters, limit) do
    all_entries(vault_path)
    |> Enum.filter(fn entry ->
      Enum.all?(filters, fn {key, value} ->
        case key do
          "tags" ->
            tags = if is_list(value), do: value, else: [value]
            tags_lower = Enum.map(tags, &String.downcase/1)
            entry_tags_lower = Enum.map(entry.tags, &String.downcase/1)
            Enum.all?(tags_lower, fn t -> t in entry_tags_lower end)

          "date_from" ->
            entry.date != nil and entry.date >= value

          "date_to" ->
            entry.date != nil and entry.date <= value

          "author" ->
            entry.author != nil and
              String.contains?(String.downcase(entry.author), String.downcase(value))

          "product" ->
            entry.product != nil and
              String.contains?(String.downcase(entry.product), String.downcase(value))

          _ ->
            meta_val = Map.get(entry.metadata, key)

            meta_val != nil and
              String.contains?(
                String.downcase(to_string(meta_val)),
                String.downcase(to_string(value))
              )
        end
      end)
    end)
    |> Enum.take(limit)
    |> Enum.map(&entry_to_result/1)
  end

  # --- Helpers ---

  defp all_entries(vault_path) do
    :ets.match_object(@table, {{vault_path, :_}, :_})
    |> Enum.map(fn {_key, entry} -> entry end)
  end

  defp entry_to_result(entry) do
    %{
      path: entry.path,
      title: entry.title,
      tags: entry.tags,
      date: entry.date,
      author: entry.author,
      product: entry.product,
      snippet: String.slice(entry.content_preview, 0, 200)
    }
  end

  defp split_frontmatter(content) do
    case Regex.run(~r/\A---\s*\n([\s\S]*?)\n---\s*\n([\s\S]*)\z/, content) do
      [_, fm, body] -> {fm, body}
      _ -> {"", content}
    end
  end

  defp parse_frontmatter_map(yaml_str) when yaml_str == "", do: %{}

  defp parse_frontmatter_map(yaml_str) do
    yaml_str
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> parse_yaml_lines(%{}, nil)
  end

  defp parse_yaml_lines([], acc, _), do: acc

  defp parse_yaml_lines([line | rest], acc, current_list_key) do
    trimmed = String.trim(line)

    cond do
      String.starts_with?(trimmed, "- ") and current_list_key != nil ->
        value = String.trim_leading(trimmed, "- ") |> String.trim()
        existing = Map.get(acc, current_list_key, [])

        parse_yaml_lines(
          rest,
          Map.put(acc, current_list_key, existing ++ [value]),
          current_list_key
        )

      String.ends_with?(trimmed, ":") ->
        key = String.trim_trailing(trimmed, ":")
        parse_yaml_lines(rest, acc, key)

      String.contains?(trimmed, ": ") ->
        [key | value_parts] = String.split(trimmed, ": ", parts: 2)
        value = Enum.join(value_parts, ": ") |> String.trim() |> unquote_value()
        parse_yaml_lines(rest, Map.put(acc, key, value), nil)

      true ->
        parse_yaml_lines(rest, acc, current_list_key)
    end
  end

  defp unquote_value("\"" <> rest), do: String.trim_trailing(rest, "\"")
  defp unquote_value("'" <> rest), do: String.trim_trailing(rest, "'")
  defp unquote_value(other), do: other

  defp file_mtime(path) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} -> mtime
      _ -> nil
    end
  end
end
