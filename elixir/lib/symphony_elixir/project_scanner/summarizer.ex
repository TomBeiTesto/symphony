defmodule SymphonyElixir.ProjectScanner.Summarizer do
  @moduledoc """
  Heuristic extraction of project name and description from README files
  and package manifest files (package.json, mix.exs, Cargo.toml, etc.).

  Prefers structured "About" / "Overview" sections over the first paragraph,
  and falls back to package file descriptions when the README is unhelpful.
  """

  @max_readme_bytes 12_000
  @readme_names ~w(README.md README.MD readme.md README Readme.md README.rst README.txt)
  @max_description 300

  @type summary :: %{name: String.t(), description: String.t() | nil}

  @doc "Extract a project name and description from a directory."
  @spec summarize(String.t()) :: summary()
  def summarize(dir_path) do
    dir_name = Path.basename(dir_path)
    readme = read_readme(dir_path)

    {title, description} =
      case readme do
        nil -> {nil, nil}
        content -> extract_from_readme(content)
      end

    # Fall back to package file descriptions when README is missing or unhelpful
    description = description || extract_from_package_files(dir_path)
    title = title || extract_name_from_package_files(dir_path)
    title = title || humanize(dir_name)

    %{name: title, description: truncate(description)}
  end

  # --- README parsing ---

  defp read_readme(dir_path) do
    Enum.find_value(@readme_names, fn name ->
      path = Path.join(dir_path, name)

      if File.regular?(path) do
        case File.read(path) do
          {:ok, content} -> String.slice(content, 0, @max_readme_bytes)
          _ -> nil
        end
      end
    end)
  end

  defp extract_from_readme(content) do
    lines = String.split(content, ~r/\r?\n/)
    title = extract_title(lines)
    description = extract_about_section(lines) || extract_first_paragraph(lines)
    {title, description}
  end

  defp extract_title(lines) do
    Enum.find_value(lines, fn line ->
      case Regex.run(~r/^#\s+(.+)/, String.trim(line)) do
        [_, heading] ->
          cleaned = strip_badges_from_heading(String.trim(heading))
          if useful_title?(cleaned), do: cleaned, else: nil

        _ ->
          nil
      end
    end)
  end

  defp strip_badges_from_heading(text) do
    text
    |> String.replace(~r/\[!\[[^\]]*\]\([^\)]*\)\]\([^\)]*\)/, "")
    |> String.replace(~r/!\[[^\]]*\]\([^\)]*\)/, "")
    |> String.trim()
  end

  @doc false
  def useful_title?(nil), do: false
  def useful_title?(""), do: false

  def useful_title?(title) do
    down = String.downcase(title)
    # Reject generic titles
    down not in ["readme", "readme.md", "documentation", "docs", "table of contents", "toc"]
  end

  @about_headings ~r/^##\s+(About|Overview|Introduction|Summary|What is|Description)/i

  defp extract_about_section(lines) do
    case find_section(lines, @about_headings) do
      nil -> nil
      section_lines -> collect_paragraph(section_lines)
    end
  end

  defp find_section(lines, heading_pattern) do
    lines
    |> Enum.with_index()
    |> Enum.find_value(fn {line, idx} ->
      if Regex.match?(heading_pattern, String.trim(line)) do
        lines
        |> Enum.drop(idx + 1)
        |> Enum.take_while(fn l ->
          trimmed = String.trim(l)
          not (String.starts_with?(trimmed, "#") and not String.starts_with?(trimmed, "#!"))
        end)
      end
    end)
  end

  defp extract_first_paragraph(lines) do
    lines
    |> Enum.drop_while(&skip_line?/1)
    |> collect_paragraph()
  end

  defp collect_paragraph(lines) do
    result =
      lines
      |> Enum.drop_while(fn l -> String.trim(l) == "" end)
      |> Enum.take_while(fn l ->
        trimmed = String.trim(l)
        trimmed != "" and not String.starts_with?(trimmed, "#")
      end)
      |> Enum.reject(&skip_line?/1)
      |> Enum.map(&String.trim/1)
      |> Enum.join(" ")

    if result == "", do: nil, else: result
  end

  defp skip_line?(line) do
    trimmed = String.trim(line)

    trimmed == "" or
      String.starts_with?(trimmed, "#") or
      String.starts_with?(trimmed, "---") or
      String.starts_with?(trimmed, "![") or
      String.starts_with?(trimmed, "[![") or
      String.starts_with?(trimmed, "<") or
      String.starts_with?(trimmed, "```") or
      Regex.match?(~r/^\|/, trimmed)
  end

  # --- Package file fallbacks ---

  @doc false
  def extract_from_package_files(dir_path) do
    extractors = [
      {"package.json", &parse_package_json_desc/1},
      {"mix.exs", &parse_mix_exs_desc/1},
      {"Cargo.toml", &parse_toml_desc/1},
      {"pyproject.toml", &parse_toml_desc/1},
      {"setup.cfg", &parse_setup_cfg_desc/1}
    ]

    Enum.find_value(extractors, fn {file, parser} ->
      path = Path.join(dir_path, file)

      if File.regular?(path) do
        case File.read(path) do
          {:ok, content} -> parser.(content)
          _ -> nil
        end
      end
    end)
  end

  defp extract_name_from_package_files(dir_path) do
    extractors = [
      {"package.json", &parse_package_json_name/1},
      {"mix.exs", &parse_mix_exs_name/1},
      {"Cargo.toml", &parse_toml_name/1}
    ]

    Enum.find_value(extractors, fn {file, parser} ->
      path = Path.join(dir_path, file)

      if File.regular?(path) do
        case File.read(path) do
          {:ok, content} -> parser.(content)
          _ -> nil
        end
      end
    end)
  end

  defp parse_package_json_desc(content) do
    case Regex.run(~r/"description"\s*:\s*"([^"]+)"/, content) do
      [_, desc] -> non_empty(desc)
      _ -> nil
    end
  end

  defp parse_package_json_name(content) do
    case Regex.run(~r/"name"\s*:\s*"([^"]+)"/, content) do
      [_, name] ->
        name
        |> String.replace(~r/^@[^\/]+\//, "")
        |> humanize()
        |> non_empty()

      _ ->
        nil
    end
  end

  defp parse_mix_exs_desc(content) do
    case Regex.run(~r/description:\s*"([^"]+)"/, content) do
      [_, desc] -> non_empty(desc)
      _ -> nil
    end
  end

  defp parse_mix_exs_name(content) do
    case Regex.run(~r/app:\s*:(\w+)/, content) do
      [_, name] -> humanize(name)
      _ -> nil
    end
  end

  defp parse_toml_desc(content) do
    case Regex.run(~r/description\s*=\s*"([^"]+)"/, content) do
      [_, desc] -> non_empty(desc)
      _ -> nil
    end
  end

  defp parse_toml_name(content) do
    case Regex.run(~r/name\s*=\s*"([^"]+)"/, content) do
      [_, name] -> humanize(name)
      _ -> nil
    end
  end

  defp parse_setup_cfg_desc(content) do
    case Regex.run(~r/description\s*=\s*(.+)/, content) do
      [_, desc] -> non_empty(String.trim(desc))
      _ -> nil
    end
  end

  # --- Helpers ---

  defp non_empty(""), do: nil
  defp non_empty(s), do: s

  defp truncate(nil), do: nil

  defp truncate(text) when byte_size(text) > @max_description do
    String.slice(text, 0, @max_description - 3) <> "..."
  end

  defp truncate(text), do: text

  defp humanize(name) do
    name
    |> String.replace(~r/[-_]+/, " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
