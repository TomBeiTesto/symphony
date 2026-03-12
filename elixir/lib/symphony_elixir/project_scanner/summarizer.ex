defmodule SymphonyElixir.ProjectScanner.Summarizer do
  @moduledoc """
  Intelligent project summarization from directory contents.

  Extracts:
  - **Title**: cleaned project name from README headings or package files
  - **Description**: concise summary from About/Overview sections or package descriptions
  - **Tags**: auto-inferred from tech stack, frameworks, and domain keywords
  """

  @max_readme_bytes 12_000
  @readme_names ~w(README.md README.MD readme.md README Readme.md README.rst README.txt)
  @max_description 300

  @type summary :: %{name: String.t(), description: String.t() | nil, tags: [String.t()]}

  @doc "Extract project name, description, and tags from a directory."
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

    # Clean up garbage titles
    title = clean_title(title, dir_name)

    tags = infer_tags(dir_path, readme)

    %{name: title, description: truncate(description), tags: Enum.uniq(tags)}
  end

  # --- Title cleaning ---

  @garbage_patterns [
    ~r/^-{2,}\s*/,
    ~r/\s*-{2,}$/,
    ~r/^={2,}\s*/,
    ~r/\s*={2,}$/,
    ~r/^automatically generated/i,
    ~r/^auto[- ]?generated/i,
    ~r/^service information/i
  ]

  defp clean_title(title, dir_name) do
    cleaned =
      Enum.reduce(@garbage_patterns, title, fn pattern, acc ->
        String.replace(acc, pattern, "")
      end)
      |> String.trim()
      |> String.trim("-")
      |> String.trim()

    if useful_title?(cleaned), do: cleaned, else: humanize(dir_name)
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

    down not in [
      "readme",
      "readme.md",
      "documentation",
      "docs",
      "table of contents",
      "toc"
    ] and
      String.length(title) > 1 and
      String.length(title) < 120
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

  # --- Tag inference ---

  @doc false
  @spec infer_tags(String.t(), String.t() | nil) :: [String.t()]
  def infer_tags(dir_path, readme_content) do
    language_tags = detect_language_tags(dir_path)
    framework_tags = detect_framework_tags(dir_path)
    infra_tags = detect_infra_tags(dir_path)
    domain_tags = if readme_content, do: detect_domain_tags(readme_content), else: []

    (language_tags ++ framework_tags ++ infra_tags ++ domain_tags)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @language_markers %{
    "mix.exs" => "elixir",
    "package.json" => "javascript",
    "Cargo.toml" => "rust",
    "go.mod" => "go",
    "pyproject.toml" => "python",
    "setup.py" => "python",
    "requirements.txt" => "python",
    "Gemfile" => "ruby",
    "build.gradle" => "java",
    "pom.xml" => "java",
    "CMakeLists.txt" => "c++",
    ".sln" => ".net",
    ".csproj" => ".net",
    "composer.json" => "php"
  }

  defp detect_language_tags(dir_path) do
    @language_markers
    |> Enum.filter(fn {marker, _} -> File.regular?(Path.join(dir_path, marker)) end)
    |> Enum.map(fn {_, lang} -> lang end)
    |> Enum.uniq()
  end

  @framework_indicators %{
    "next.config.js" => "nextjs",
    "next.config.mjs" => "nextjs",
    "next.config.ts" => "nextjs",
    "nuxt.config.ts" => "nuxt",
    "angular.json" => "angular",
    "vite.config.ts" => "vite",
    "webpack.config.js" => "webpack",
    "tailwind.config.js" => "tailwind",
    "tailwind.config.ts" => "tailwind",
    "tsconfig.json" => "typescript",
    "jest.config.js" => "jest",
    "playwright.config.ts" => "playwright",
    ".eslintrc.json" => "eslint",
    "terraform.tf" => "terraform",
    "serverless.yml" => "serverless",
    "samconfig.toml" => "aws-sam",
    "template.yaml" => "cloudformation",
    "cdk.json" => "aws-cdk",
    "pulumi.yaml" => "pulumi"
  }

  defp detect_framework_tags(dir_path) do
    @framework_indicators
    |> Enum.filter(fn {file, _} -> File.regular?(Path.join(dir_path, file)) end)
    |> Enum.map(fn {_, tag} -> tag end)
  end

  defp detect_infra_tags(dir_path) do
    tags = []

    tags =
      if File.regular?(Path.join(dir_path, "Dockerfile")) or
           File.regular?(Path.join(dir_path, "docker-compose.yml")) or
           File.regular?(Path.join(dir_path, "docker-compose.yaml")),
         do: ["docker" | tags],
         else: tags

    tags =
      if File.dir?(Path.join(dir_path, ".github")),
        do: ["github-actions" | tags],
        else: tags

    tags =
      if File.regular?(Path.join(dir_path, ".gitlab-ci.yml")),
        do: ["gitlab-ci" | tags],
        else: tags

    tags =
      if File.regular?(Path.join(dir_path, "Jenkinsfile")),
        do: ["jenkins" | tags],
        else: tags

    tags =
      if File.dir?(Path.join(dir_path, "k8s")) or
           File.dir?(Path.join(dir_path, "kubernetes")) or
           File.dir?(Path.join(dir_path, "helm")),
         do: ["kubernetes" | tags],
         else: tags

    tags
  end

  @domain_keywords %{
    ~r/\b(stream|streaming|kafka|kinesis|event[ -]?driven)\b/i => "streaming",
    ~r/\b(ETL|data[ -]?pipeline|airflow|glue|spark)\b/i => "data-pipeline",
    ~r/\b(REST|API|endpoint|microservice|graphql)\b/i => "api",
    ~r/\b(machine[ -]?learn|ML|model|training|inference)\b/i => "ml",
    ~r/\b(monitor|alert|observ|prometheus|grafana|datadog)\b/i => "monitoring",
    ~r/\b(auth|oauth|JWT|SSO|SAML|identity)\b/i => "auth",
    ~r/\b(database|postgres|mysql|dynamo|redis|cassandra)\b/i => "database",
    ~r/\b(message[ -]?broker|queue|RabbitMQ|SQS|ActiveMQ|AMQP)\b/i => "messaging",
    ~r/\b(infrastructure|IaC|terraform|cloudformation|provisioning)\b/i => "infrastructure",
    ~r/\b(CI\/CD|deploy|pipeline|release)\b/i => "ci-cd",
    ~r/\b(frontend|UI|user[ -]?interface|react|vue|angular)\b/i => "frontend",
    ~r/\b(backend|server|service)\b/i => "backend"
  }

  defp detect_domain_tags(readme_content) do
    # Only scan first 3000 chars to stay fast
    snippet = String.slice(readme_content, 0, 3000)

    @domain_keywords
    |> Enum.filter(fn {pattern, _} -> Regex.match?(pattern, snippet) end)
    |> Enum.map(fn {_, tag} -> tag end)
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
