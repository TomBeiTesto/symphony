defmodule SymphonyElixir.ShellUtils do
  @moduledoc """
  Centralised shell detection and command building utilities.

  Provides OS detection, bash location, and shell command construction
  used across workspace hooks and app-server subprocess management.
  """

  @doc "Returns `true` when running on Windows."
  @spec windows?() :: boolean()
  def windows? do
    match?({:win32, _}, :os.type())
  end

  @doc """
  Locate a bash executable on the system.

  Checks `PATH` first, then well-known Windows install locations.
  Returns `nil` when bash cannot be found.
  """
  @spec find_bash_path() :: String.t() | nil
  def find_bash_path do
    System.find_executable("bash") || find_bash_windows()
  end

  @doc """
  Build `{executable, args}` for running `script` under the given shell.

  When `shell` contains a recognisable name (bash, sh, cmd, powershell) the
  appropriate flags are chosen automatically. For unknown shells the OS type
  is used as a fallback.
  """
  @spec shell_command(String.t(), String.t()) :: {String.t(), [String.t()]}
  def shell_command(shell, script) do
    cond do
      String.contains?(shell, "bash") ->
        {shell, ["-lc", script]}

      String.contains?(shell, "sh") ->
        {shell, ["-c", script]}

      String.contains?(shell, "cmd") ->
        {shell, ["/C", script]}

      String.contains?(shell, "powershell") ->
        {shell, ["-NoProfile", "-Command", script]}

      true ->
        if windows?() do
          {shell, ["/C", script]}
        else
          {shell, ["-c", script]}
        end
    end
  end

  @doc """
  Return shell args (without the script) for a given shell executable.

  Used by `AppServer.Client` where the command is appended separately.
  """
  @spec shell_args(String.t()) :: [String.t()]
  def shell_args(shell) do
    cond do
      String.contains?(shell, "bash") -> ["-lc"]
      String.contains?(shell, "sh") -> ["-c"]
      String.contains?(shell, "cmd") -> ["/C"]
      String.contains?(shell, "powershell") -> ["-NoProfile", "-Command"]
      true -> ["-c"]
    end
  end

  @doc """
  Return a default shell executable for the current OS.

  On Windows prefers `cmd`, on Unix prefers `bash` then `sh`.
  """
  @spec default_shell() :: String.t()
  def default_shell do
    if windows?() do
      default_windows_shell()
    else
      default_unix_shell()
    end
  end

  @doc """
  Return a default shell for running hooks.

  Prefers bash on all platforms because hook scripts use bash syntax.
  Falls back to cmd on Windows or sh on Unix.
  """
  @spec default_hook_shell() :: String.t()
  def default_hook_shell do
    find_bash_path() ||
      if windows?() do
        System.find_executable("cmd") || "cmd"
      else
        System.find_executable("sh") || "/bin/sh"
      end
  end

  # --- Private helpers ---

  defp find_bash_windows do
    [
      "C:/Program Files/Git/bin/bash.exe",
      "C:/Program Files (x86)/Git/bin/bash.exe",
      "C:/msys64/usr/bin/bash.exe",
      "C:/cygwin64/bin/bash.exe"
    ]
    |> Enum.find(&File.exists?/1)
  end

  defp default_windows_shell do
    cond do
      System.find_executable("cmd") -> System.find_executable("cmd")
      System.find_executable("powershell") -> System.find_executable("powershell")
      true -> "cmd"
    end
  end

  defp default_unix_shell do
    cond do
      System.find_executable("bash") -> System.find_executable("bash")
      System.find_executable("sh") -> System.find_executable("sh")
      true -> "/bin/sh"
    end
  end
end
