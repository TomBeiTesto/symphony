defmodule SymphonyElixir.ProjectScanner.Git do
  @moduledoc "Git operations for the project scanner: pull, branch detection, remote URL."

  require Logger

  @pull_timeout_ms 30_000

  @doc "Pull latest from the default branch. Skips if worktree is dirty or no .git."
  @spec pull_latest(String.t()) :: {:ok, String.t()} | {:error, String.t()} | {:skipped, atom()}
  def pull_latest(dir_path) do
    cond do
      not has_git?(dir_path) ->
        {:skipped, :no_git}

      not clean_worktree?(dir_path) ->
        {:skipped, :dirty_worktree}

      true ->
        branch = detect_default_branch(dir_path)

        task =
          Task.async(fn ->
            System.cmd("git", ["pull", "origin", branch],
              cd: dir_path,
              stderr_to_stdout: true
            )
          end)

        case Task.yield(task, @pull_timeout_ms) || Task.shutdown(task, :brutal_kill) do
          {:ok, {_out, 0}} ->
            Logger.info("Git pull succeeded for #{dir_path} (#{branch})")
            {:ok, branch}

          {:ok, {out, _code}} ->
            Logger.warning("Git pull failed for #{dir_path}: #{String.trim(out)}")
            {:error, String.trim(out)}

          nil ->
            Logger.warning("Git pull timed out for #{dir_path}")
            {:error, "pull timed out after #{@pull_timeout_ms}ms"}
        end
    end
  rescue
    e ->
      {:error, Exception.message(e)}
  end

  @doc "Detect the default branch from .git/HEAD."
  @spec detect_default_branch(String.t()) :: String.t()
  def detect_default_branch(dir_path) do
    head_path = Path.join([dir_path, ".git", "HEAD"])

    case File.read(head_path) do
      {:ok, content} ->
        case Regex.run(~r/ref: refs\/heads\/(.+)/, String.trim(content)) do
          [_, branch] -> String.trim(branch)
          _ -> "main"
        end

      _ ->
        "main"
    end
  end

  @doc "Read the remote origin URL from .git/config."
  @spec detect_remote_url(String.t()) :: String.t() | nil
  def detect_remote_url(dir_path) do
    config_path = Path.join([dir_path, ".git", "config"])

    if File.regular?(config_path) do
      case File.read(config_path) do
        {:ok, content} ->
          case Regex.run(~r/\[remote "origin"\][^\[]*url\s*=\s*(.+)/s, content) do
            [_, url] -> url |> String.split("\n") |> List.first() |> String.trim()
            _ -> nil
          end

        _ ->
          nil
      end
    end
  end

  @doc "Check if a directory has a .git folder."
  @spec has_git?(String.t()) :: boolean()
  def has_git?(dir_path), do: File.dir?(Path.join(dir_path, ".git"))

  defp clean_worktree?(dir_path) do
    case System.cmd("git", ["status", "--porcelain"], cd: dir_path, stderr_to_stdout: true) do
      {"", 0} -> true
      {_, 0} -> false
      _ -> false
    end
  rescue
    _ -> false
  end
end
