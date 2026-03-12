defmodule SymphonyElixir.ProjectScanner.AgentSummarizer do
  @moduledoc """
  AI-powered project summarization using Claude.

  Sends a batch of raw project data to Claude via `claude -p` and receives
  structured JSON with intelligent names, descriptions, and tags for each project.
  Falls back to the heuristic `Summarizer` if the agent call fails.
  """

  require Logger

  alias SymphonyElixir.ShellUtils

  @max_readme_chars 3000
  @max_file_list 60
  @timeout_ms 120_000

  @doc """
  Enrich a list of raw candidates with AI-generated summaries.

  Each candidate must have at least `:path` and `:slug`.
  Returns the same list with `:name`, `:description`, and `:tags` potentially
  replaced by more intelligent values from the agent.
  """
  @spec enrich(list(map())) :: list(map())
  def enrich([]), do: []

  def enrich(candidates) do
    case call_agent(candidates) do
      {:ok, enriched_map} ->
        Enum.map(candidates, fn c ->
          case Map.get(enriched_map, c.path) do
            nil -> c
            ai -> merge_ai_summary(c, ai)
          end
        end)

      {:error, reason} ->
        Logger.warning("Agent summarizer failed (#{inspect(reason)}), using heuristic summaries")
        candidates
    end
  end

  # --- Agent call ---

  defp call_agent(candidates) do
    bash = ShellUtils.find_bash_path()

    unless bash do
      {:error, :bash_not_found}
    else
      context = build_context(candidates)
      prompt = build_prompt(context)

      run_claude(bash, prompt)
    end
  end

  defp run_claude(bash, prompt) do
    # Write prompt to temp file
    prompt_file =
      Path.join(System.tmp_dir!(), "symphony_scan_prompt_#{:rand.uniform(999_999)}.txt")

    try do
      File.write!(prompt_file, prompt)

      claude_cmd = (System.find_executable("claude") && "claude") || "claude"

      shell_command =
        "cat #{shell_escape(prompt_file)} | #{claude_cmd} -p --output-format json 2>/dev/null"

      env = [
        {~c"CLAUDECODE", false},
        {~c"CLAUDE_CODE_ENTRYPOINT", false}
      ]

      port_opts = [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:args, ["-lc", shell_command]},
        {:env, env},
        {:line, 1_048_576}
      ]

      port = Port.open({:spawn_executable, bash}, port_opts)
      result = collect_output(port, "", @timeout_ms)

      case result do
        {:ok, output} -> parse_agent_response(output)
        {:error, _} = err -> err
      end
    after
      File.rm(prompt_file)
    end
  rescue
    e -> {:error, {:agent_error, Exception.message(e)}}
  end

  defp collect_output(port, acc, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    do_collect(port, acc, deadline)
  end

  defp do_collect(port, acc, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, {:eol, line}}} ->
        do_collect(port, acc <> line <> "\n", deadline)

      {^port, {:data, {:noeol, chunk}}} ->
        do_collect(port, acc <> chunk, deadline)

      {^port, {:exit_status, 0}} ->
        {:ok, acc}

      {^port, {:exit_status, code}} ->
        {:error, {:exit_code, code, acc}}
    after
      remaining ->
        safe_kill_port(port)
        {:error, :timeout}
    end
  end

  # --- Prompt building ---

  defp build_context(candidates) do
    Enum.map(candidates, fn c ->
      dir = c.path

      %{
        path: dir,
        dir_name: Path.basename(dir),
        readme: read_readme_snippet(dir),
        files: list_top_files(dir),
        package_info: read_package_info(dir)
      }
    end)
  end

  defp build_prompt(projects_context) do
    projects_json = Jason.encode!(projects_context, pretty: true)

    """
    You are a project analyzer. Given the following list of software projects (with their directory contents), generate a structured summary for each one.

    For each project, return:
    - "name": A clean, human-readable project name (title case, no garbage like "---" or "auto-generated"). Use the README title if good, otherwise derive from package metadata or directory name.
    - "description": A concise 1-2 sentence description of what the project does. Extract from README About/Overview sections, package description fields, or infer from the tech stack and file structure. Max 250 characters.
    - "tags": An array of lowercase tags covering: programming languages used, frameworks, infrastructure tools, and domain categories (e.g. "api", "data-pipeline", "ml", "frontend", "monitoring", "auth", "database", "streaming", "messaging").

    IMPORTANT: Respond with ONLY a JSON array. No markdown, no code fences, no explanation. Each element must have "path", "name", "description", and "tags" keys.

    Projects to analyze:

    #{projects_json}
    """
  end

  defp read_readme_snippet(dir) do
    readme_names = ~w(README.md README.MD readme.md README Readme.md README.rst README.txt)

    Enum.find_value(readme_names, fn name ->
      path = Path.join(dir, name)

      if File.regular?(path) do
        case File.read(path) do
          {:ok, content} -> String.slice(content, 0, @max_readme_chars)
          _ -> nil
        end
      end
    end)
  end

  defp list_top_files(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> Enum.take(@max_file_list)

      _ ->
        []
    end
  end

  defp read_package_info(dir) do
    pkg_files = [
      {"package.json", &read_file_snippet/1},
      {"mix.exs", &read_file_snippet/1},
      {"Cargo.toml", &read_file_snippet/1},
      {"pyproject.toml", &read_file_snippet/1},
      {"go.mod", &read_file_snippet/1},
      {"setup.py", &read_file_snippet/1},
      {"build.gradle", &read_file_snippet/1},
      {"pom.xml", &read_file_snippet/1},
      {"Gemfile", &read_file_snippet/1},
      {"composer.json", &read_file_snippet/1}
    ]

    Enum.find_value(pkg_files, fn {file, reader} ->
      path = Path.join(dir, file)
      if File.regular?(path), do: %{file: file, content: reader.(path)}
    end)
  end

  defp read_file_snippet(path) do
    case File.read(path) do
      {:ok, content} -> String.slice(content, 0, 2000)
      _ -> nil
    end
  end

  # --- Response parsing ---

  defp parse_agent_response(output) do
    # The output from `claude -p --output-format json` wraps the result
    # in a JSON object with a "result" key containing the text.
    text =
      case Jason.decode(String.trim(output)) do
        {:ok, %{"result" => result}} when is_binary(result) -> result
        {:ok, list} when is_list(list) -> output
        _ -> output
      end

    # Strip markdown code fences if present
    text =
      text
      |> String.trim()
      |> String.replace(~r/^```json\s*/i, "")
      |> String.replace(~r/\s*```$/, "")
      |> String.trim()

    case Jason.decode(text) do
      {:ok, list} when is_list(list) ->
        enriched =
          Map.new(list, fn item ->
            {item["path"],
             %{
               name: item["name"],
               description: item["description"],
               tags: item["tags"] || []
             }}
          end)

        {:ok, enriched}

      {:ok, _other} ->
        {:error, :unexpected_response_shape}

      {:error, reason} ->
        # Try to find a JSON array in the output
        case Regex.run(~r/\[[\s\S]*\]/, text) do
          [json_str] ->
            case Jason.decode(json_str) do
              {:ok, list} when is_list(list) ->
                enriched =
                  Map.new(list, fn item ->
                    {item["path"],
                     %{
                       name: item["name"],
                       description: item["description"],
                       tags: item["tags"] || []
                     }}
                  end)

                {:ok, enriched}

              _ ->
                {:error, {:json_parse_failed, reason}}
            end

          nil ->
            {:error, {:json_parse_failed, reason}}
        end
    end
  end

  defp merge_ai_summary(candidate, ai) do
    candidate
    |> maybe_replace(:name, ai[:name])
    |> maybe_replace(:description, ai[:description])
    |> maybe_replace(:tags, ai[:tags])
  end

  defp maybe_replace(map, _key, nil), do: map
  defp maybe_replace(map, _key, ""), do: map
  defp maybe_replace(map, _key, []), do: map
  defp maybe_replace(map, key, value), do: Map.put(map, key, value)

  # --- Helpers ---

  defp shell_escape(path) do
    "'" <> String.replace(path, "'", "'\\''") <> "'"
  end

  defp safe_kill_port(port) do
    try do
      case Port.info(port, :os_pid) do
        {:os_pid, pid} ->
          if match?({:win32, _}, :os.type()) do
            System.cmd("taskkill", ["/F", "/T", "/PID", "#{pid}"], stderr_to_stdout: true)
          else
            System.cmd("kill", ["-9", "#{pid}"], stderr_to_stdout: true)
          end

        _ ->
          :ok
      end

      Port.close(port)
    rescue
      _ -> :ok
    end
  end
end
