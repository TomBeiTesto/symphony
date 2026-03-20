defmodule SymphonyElixir.ProjectScanner do
  @moduledoc """
  Intelligent recursive directory scanner for project discovery.

  Traverses a root directory tree and identifies real projects by looking
  for git repositories and/or project marker files (mix.exs, package.json, etc.).
  Non-project directories are recursively explored to find nested projects.

  Features:
  - True recursive discovery: if a dir is not a project, recurse into children
  - Git pull before scanning (optional)
  - Smart summarization with tag inference via Summarizer
  - Parallel scanning with bounded concurrency
  """

  require Logger

  alias SymphonyElixir.ProjectScanner.{AgentSummarizer, Git, Summarizer}

  @project_markers ~w(mix.exs package.json Cargo.toml go.mod pyproject.toml setup.py
                       build.gradle pom.xml CMakeLists.txt Makefile Gemfile requirements.txt
                       .sln .csproj composer.json Dockerfile docker-compose.yml)

  @max_concurrency 8
  @max_depth 5

  @skip_dirs ~w(node_modules .git __pycache__ .venv venv .tox dist build target
                _build deps .elixir_ls .next .cache .terraform)

  @type scan_opts :: [
          git_pull: boolean(),
          recursive: boolean()
        ]

  @type scanned_project :: %{
          name: String.t(),
          slug: String.t(),
          path: String.t(),
          description: String.t() | nil,
          repo_url: String.t() | nil,
          git_branch: String.t() | nil,
          tags: [String.t()]
        }

  @doc """
  Scan a root directory and return a list of discovered projects.

  Recursively explores the directory tree. A directory is considered a project
  if it has a `.git` directory or contains project marker files. Non-project
  directories are recursively explored up to #{@max_depth} levels deep.

  ## Options

    * `:git_pull` - pull latest from default branch before scanning (default: `false`)
    * `:recursive` - kept for API compat, scanning is always recursive now (default: `true`)
  """
  @spec scan(String.t(), scan_opts()) :: {:ok, [scanned_project()]} | {:error, term()}
  def scan(root_path, opts \\ []) do
    expanded = expand_path(root_path)

    if File.dir?(expanded) do
      git_pull? = Keyword.get(opts, :git_pull, false)
      ai? = Keyword.get(opts, :ai_summarize, false)

      candidates = discover_projects(expanded, 0, git_pull?)

      candidates =
        if ai? and candidates != [] do
          AgentSummarizer.enrich(candidates)
        else
          candidates
        end

      {:ok, candidates}
    else
      {:error, :not_a_directory}
    end
  rescue
    e -> {:error, {:scan_failed, Exception.message(e)}}
  end

  # --- Recursive discovery ---

  defp discover_projects(dir_path, depth, git_pull?) when depth >= @max_depth do
    # At max depth, try to make a candidate even without markers
    if is_project?(dir_path) do
      [build_candidate(dir_path, git_pull?)]
    else
      []
    end
  end

  defp discover_projects(dir_path, depth, git_pull?) do
    subdirs =
      dir_path
      |> list_subdirs()
      |> Enum.sort()

    if depth == 0 do
      # Top-level: parallel scan
      subdirs
      |> Task.async_stream(
        fn dir -> scan_subtree(dir, depth + 1, git_pull?) end,
        max_concurrency: @max_concurrency,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, results} -> results
        {:exit, _reason} -> []
      end)
    else
      Enum.flat_map(subdirs, fn dir ->
        scan_subtree(dir, depth + 1, git_pull?)
      end)
    end
  end

  defp scan_subtree(dir_path, depth, git_pull?) do
    cond do
      # Has .git → this is a project root. Don't recurse further into git repos.
      Git.has_git?(dir_path) ->
        projects = [build_candidate(dir_path, git_pull?)]

        # Also check for monorepo sub-projects within this git repo
        sub_projects = find_monorepo_children(dir_path)
        projects ++ sub_projects

      # Has project markers but no git → standalone project (e.g., subdirectory project)
      has_project_marker?(dir_path) ->
        [build_candidate(dir_path, git_pull?)]

      # Not a project → recurse deeper
      true ->
        discover_projects(dir_path, depth, git_pull?)
    end
  end

  defp find_monorepo_children(git_root) do
    # Look for common monorepo container dirs
    monorepo_containers = ~w(apps packages services modules libs projects crates workspaces src)

    monorepo_containers
    |> Enum.map(&Path.join(git_root, &1))
    |> Enum.filter(&File.dir?/1)
    |> Enum.flat_map(&list_subdirs/1)
    |> Enum.filter(&has_project_marker?/1)
    |> Enum.map(&build_candidate(&1, false))
  end

  defp build_candidate(dir_path, git_pull?) do
    dir_name = Path.basename(dir_path)
    git_branch = if git_pull?, do: maybe_git_pull(dir_path), else: nil
    summary = Summarizer.summarize(dir_path)

    %{
      name: summary.name,
      slug: SymphonyElixir.LocalBoard.Helpers.slugify(dir_name),
      path: dir_path,
      description: summary.description,
      repo_url: Git.detect_remote_url(dir_path) || detect_parent_remote(dir_path),
      git_branch: git_branch,
      tags: summary.tags
    }
  end

  # --- Detection helpers ---

  defp is_project?(dir_path) do
    Git.has_git?(dir_path) or has_project_marker?(dir_path)
  end

  defp has_project_marker?(dir_path) do
    Enum.any?(@project_markers, fn marker ->
      File.regular?(Path.join(dir_path, marker))
    end)
  end

  defp detect_parent_remote(dir_path) do
    parent = Path.dirname(dir_path)
    grandparent = Path.dirname(parent)

    cond do
      Git.has_git?(parent) -> Git.detect_remote_url(parent)
      Git.has_git?(grandparent) -> Git.detect_remote_url(grandparent)
      true -> nil
    end
  end

  defp maybe_git_pull(dir_path) do
    case Git.pull_latest(dir_path) do
      {:ok, branch} -> branch
      {:skipped, _} -> nil
      {:error, _} -> nil
    end
  end

  # --- Utility ---

  defp list_subdirs(dir_path) do
    case File.ls(dir_path) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&skip_dir?/1)
        |> Enum.map(&Path.join(dir_path, &1))
        |> Enum.filter(&File.dir?/1)

      _ ->
        []
    end
  end

  defp skip_dir?(name) do
    String.starts_with?(name, ".") or name in @skip_dirs
  end

  defp expand_path("~" <> rest), do: Path.expand(System.user_home!() <> rest)
  defp expand_path(path), do: Path.expand(path)
end
