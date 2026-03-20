defmodule SymphonyElixir.LocalBoard.Projects do
  @moduledoc """
  Project-related operations for the local board.

  Handles CRUD for projects and repository cloning.
  All functions receive and return the board state struct.
  """

  require Logger

  alias SymphonyElixir.LocalBoard.Persistence

  import SymphonyElixir.LocalBoard.Helpers

  # --- handle_call delegates ---

  def list_projects(board) do
    projects = board.projects |> Map.values() |> Enum.sort_by(& &1.name)
    {:reply, projects, board}
  end

  def get_project(board, id) do
    case Map.get(board.projects, id) do
      nil -> {:reply, {:error, :not_found}, board}
      project -> {:reply, {:ok, project}, board}
    end
  end

  def create_project(board, attrs) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    id = generate_id()
    name = Map.get(attrs, "name", "Untitled Project")
    slug = Map.get(attrs, "slug") || slugify(name)

    project = %{
      id: id,
      name: name,
      slug: slug,
      path: Map.get(attrs, "path"),
      repo_url: Map.get(attrs, "repo_url"),
      description: Map.get(attrs, "description"),
      tags: parse_labels(Map.get(attrs, "tags", [])),
      priority: parse_priority(Map.get(attrs, "priority", 0)),
      created_at: now,
      updated_at: now
    }

    board = %{board | projects: Map.put(board.projects, id, project)}
    Persistence.persist(board)

    {:reply, {:ok, project}, board}
  end

  def update_project(board, id, attrs) do
    case Map.get(board.projects, id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      existing ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        updated =
          existing
          |> maybe_update(:name, attrs)
          |> maybe_update(:slug, attrs)
          |> maybe_update(:path, attrs)
          |> maybe_update(:repo_url, attrs)
          |> maybe_update(:description, attrs)
          |> maybe_update(:tags, attrs, &parse_labels/1)
          |> maybe_update(:priority, attrs, &parse_priority/1)
          |> Map.put(:updated_at, now)

        board = %{board | projects: Map.put(board.projects, id, updated)}
        Persistence.persist(board)

        {:reply, {:ok, updated}, board}
    end
  end

  def delete_project(board, id) do
    if Map.has_key?(board.projects, id) do
      # Cascade: delete all issues belonging to this project
      issues =
        board.issues
        |> Enum.reject(fn {_id, issue} -> issue.project_id == id end)
        |> Map.new()

      board = %{board | projects: Map.delete(board.projects, id), issues: issues}
      Persistence.persist(board)
      {:reply, :ok, board}
    else
      {:reply, {:error, :not_found}, board}
    end
  end

  def clone_project_repo(board, id) do
    case Map.get(board.projects, id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      %{repo_url: nil} ->
        {:reply, {:error, :no_repo_url}, board}

      %{repo_url: ""} ->
        {:reply, {:error, :no_repo_url}, board}

      project ->
        result = do_clone(project)

        case result do
          {:ok, clone_path} ->
            now = DateTime.utc_now() |> DateTime.to_iso8601()
            updated = %{project | path: clone_path, updated_at: now}
            board = %{board | projects: Map.put(board.projects, id, updated)}
            Persistence.persist(board)
            {:reply, {:ok, clone_path}, board}

          {:error, _} = err ->
            {:reply, err, board}
        end
    end
  end

  # --- Private helpers ---

  defp do_clone(%{repo_url: url, name: name}) do
    target_dir =
      Path.join([
        System.tmp_dir!(),
        "symphony_projects",
        slugify(name) <>
          "_" <> (:crypto.strong_rand_bytes(4) |> Base.url_encode64(padding: false))
      ])

    File.mkdir_p!(Path.dirname(target_dir))

    # Inject git token from Settings if available and URL is HTTPS
    clone_url = inject_git_token(url)

    case System.cmd("git", ["clone", "--depth", "1", clone_url, target_dir],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        Logger.info("Cloned #{url} to #{target_dir}")
        {:ok, target_dir}

      {output, code} ->
        Logger.error("git clone failed (exit #{code}): #{output}")
        {:error, {:clone_failed, output}}
    end
  rescue
    e -> {:error, {:clone_error, Exception.message(e)}}
  end

  defp inject_git_token(url) do
    token = safe_get_setting("git_token")
    provider = safe_get_setting("git_provider")

    if token != "" and String.starts_with?(url, "https://") do
      uri = URI.parse(url)

      userinfo =
        case provider do
          "gitlab" -> "oauth2:#{token}"
          "github" -> "x-access-token:#{token}"
          _ -> "token:#{token}"
        end

      URI.to_string(%{uri | userinfo: userinfo})
    else
      url
    end
  end

  defp safe_get_setting(key) do
    if GenServer.whereis(SymphonyElixir.Settings) do
      SymphonyElixir.Settings.get(key) || ""
    else
      ""
    end
  rescue
    e ->
      Logger.warning("Failed to get setting #{key}: #{Exception.message(e)}")
      ""
  end
end
