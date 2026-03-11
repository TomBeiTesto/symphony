defmodule SymphonyElixir.ProjectScanner do
  @moduledoc """
  Scans a root directory for subdirectories and generates project metadata.

  Supports:
  - Recursive monorepo detection (apps/, packages/, services/ etc.)
  - Git pull before scanning (optional)
  - Smart README + package file summarization via Summarizer
  - Parallel scanning with bounded concurrency
  """

  require Logger

  alias SymphonyElixir.ProjectScanner.{Git, Summarizer}

  @project_markers ~w(mix.exs package.json Cargo.toml go.mod pyproject.toml setup.py
                       build.gradle pom.xml CMakeLists.txt Makefile Gemfile requirements.txt)

  @monorepo_dirs ~w(apps packages services modules libs projects crates workspace)

  @max_concurrency 8

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
          git_branch: String.t() | nil
        }

  @doc """
  Scan a root directory and return a list of candidate projects.

  ## Options

    * `:git_pull` - pull latest from default branch before scanning (default: `false`)
    * `:recursive` - detect monorepos and scan subdirectories (default: `false`)
  """
  @spec scan(String.t(), scan_opts()) :: {:ok, [scanned_project()]} | {:error, term()}
  def scan(root_path, opts \\ []) do
    expanded = expand_path(root_path)

    if File.dir?(expanded) do
      git_pull? = Keyword.get(opts, :git_pull, false)
      recursive? = Keyword.get(opts, :recursive, false)

      dirs =
        expanded
        |> list_subdirs()
        |> Enum.sort()

      candidates =
        dirs
        |> Task.async_stream(
          fn dir -> scan_directory(dir, git_pull?: git_pull?, recursive?: recursive?) end,
          max_concurrency: @max_concurrency,
          timeout: 60_000,
          on_timeout: :kill_task
        )
        |> Enum.flat_map(fn
          {:ok, results} when is_list(results) -> results
          {:ok, result} -> [result]
          {:exit, _reason} -> []
        end)

      {:ok, candidates}
    else
      {:error, :not_a_directory}
    end
  rescue
    e -> {:error, {:scan_failed, Exception.message(e)}}
  end

  # --- Scanning ---

  defp scan_directory(dir_path, opts) do
    git_pull? = Keyword.get(opts, :git_pull?, false)
    recursive? = Keyword.get(opts, :recursive?, false)

    git_branch = maybe_git_pull(dir_path, git_pull?)

    if recursive? and monorepo?(dir_path) do
      scan_monorepo(dir_path, git_branch)
    else
      [build_candidate(dir_path, git_branch)]
    end
  end

  defp scan_monorepo(dir_path, git_branch) do
    sub_projects =
      @monorepo_dirs
      |> Enum.map(&Path.join(dir_path, &1))
      |> Enum.filter(&File.dir?/1)
      |> Enum.flat_map(&list_subdirs/1)
      |> Enum.filter(&has_project_marker?/1)
      |> Enum.map(&build_candidate(&1, git_branch))

    if sub_projects == [] do
      # Not actually a monorepo pattern we recognize; treat as single project
      [build_candidate(dir_path, git_branch)]
    else
      # Include the root as well if it has its own project marker
      root_candidates =
        if has_project_marker?(dir_path),
          do: [build_candidate(dir_path, git_branch)],
          else: []

      root_candidates ++ sub_projects
    end
  end

  defp build_candidate(dir_path, git_branch) do
    dir_name = Path.basename(dir_path)
    summary = Summarizer.summarize(dir_path)

    %{
      name: summary.name,
      slug: slugify(dir_name),
      path: dir_path,
      description: summary.description,
      repo_url: Git.detect_remote_url(dir_path) || detect_parent_remote(dir_path),
      git_branch: git_branch
    }
  end

  # For monorepo sub-projects, walk up to find the git remote
  defp detect_parent_remote(dir_path) do
    parent = Path.dirname(dir_path)
    grandparent = Path.dirname(parent)

    cond do
      Git.has_git?(parent) -> Git.detect_remote_url(parent)
      Git.has_git?(grandparent) -> Git.detect_remote_url(grandparent)
      true -> nil
    end
  end

  defp maybe_git_pull(dir_path, true) do
    case Git.pull_latest(dir_path) do
      {:ok, branch} -> branch
      {:skipped, _reason} -> nil
      {:error, _reason} -> nil
    end
  end

  defp maybe_git_pull(_dir_path, false), do: nil

  # --- Detection helpers ---

  defp monorepo?(dir_path) do
    Enum.any?(@monorepo_dirs, fn sub ->
      sub_path = Path.join(dir_path, sub)
      File.dir?(sub_path) and has_nested_projects?(sub_path)
    end)
  end

  defp has_nested_projects?(container_dir) do
    container_dir
    |> list_subdirs()
    |> Enum.any?(&has_project_marker?/1)
  end

  defp has_project_marker?(dir_path) do
    Enum.any?(@project_markers, fn marker ->
      File.regular?(Path.join(dir_path, marker))
    end)
  end

  # --- Utility ---

  defp list_subdirs(dir_path) do
    case File.ls(dir_path) do
      {:ok, entries} ->
        entries
        |> Enum.map(&Path.join(dir_path, &1))
        |> Enum.filter(&File.dir?/1)
        |> Enum.reject(&hidden?/1)

      _ ->
        []
    end
  end

  defp hidden?(path) do
    Path.basename(path) |> String.starts_with?(".")
  end

  defp expand_path("~" <> rest), do: Path.expand(System.user_home!() <> rest)
  defp expand_path(path), do: Path.expand(path)

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
