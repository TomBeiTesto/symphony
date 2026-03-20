defmodule SymphonyElixir.ProjectScanner.SummarizerTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.ProjectScanner.Summarizer

  setup do
    tmp = Path.join(System.tmp_dir!(), "summarizer_test_#{:rand.uniform(999_999)}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, root: tmp}
  end

  test "humanizes dir name when no README or package files", %{root: root} do
    result = Summarizer.summarize(root)
    assert result.description == nil
    assert is_binary(result.name)
  end

  test "extracts title and description from README", %{root: root} do
    File.write!(Path.join(root, "README.md"), """
    # My Great Tool
    
    A command-line tool for managing deployments.
    
    ## Usage
    """)

    result = Summarizer.summarize(root)
    assert result.name == "My Great Tool"
    assert result.description =~ "command-line tool"
  end

  test "prefers About section over first paragraph", %{root: root} do
    File.write!(Path.join(root, "README.md"), """
    # Repo Name
    
    [![Badge](url)]()
    
    Random badges paragraph here.
    
    ## About
    
    This tool helps automate CI/CD pipelines for Elixir projects.
    
    ## Installation
    """)

    result = Summarizer.summarize(root)
    assert result.description =~ "automate CI/CD"
  end

  test "prefers Overview section", %{root: root} do
    File.write!(Path.join(root, "README.md"), """
    # Library
    
    ## Overview
    
    A fast JSON parser written in Rust.
    
    ## API
    """)

    result = Summarizer.summarize(root)
    assert result.description =~ "fast JSON parser"
  end

  test "falls back to package.json description", %{root: root} do
    File.write!(Path.join(root, "package.json"), """
    {
      "name": "@org/my-lib",
      "version": "1.0.0",
      "description": "Shared utilities for the org"
    }
    """)

    result = Summarizer.summarize(root)
    assert result.description == "Shared utilities for the org"
  end

  test "falls back to mix.exs description", %{root: root} do
    File.write!(Path.join(root, "mix.exs"), """
    defmodule MyApp.MixProject do
      use Mix.Project
      def project do
        [app: :my_app, description: "An Elixir web framework"]
      end
    end
    """)

    result = Summarizer.summarize(root)
    assert result.description == "An Elixir web framework"
  end

  test "falls back to Cargo.toml description", %{root: root} do
    File.write!(Path.join(root, "Cargo.toml"), """
    [package]
    name = "fast-parser"
    description = "A blazing fast parser"
    """)

    result = Summarizer.summarize(root)
    assert result.description == "A blazing fast parser"
  end

  test "rejects generic README titles", %{root: root} do
    File.write!(Path.join(root, "README.md"), """
    # README
    
    Actual content here.
    """)

    result = Summarizer.summarize(root)
    # Should not use "README" as the name
    assert result.name != "README"
  end

  test "strips badges from heading", %{root: root} do
    File.write!(Path.join(root, "README.md"), """
    # My Project ![CI](badge.svg) [![Docs](docs.svg)](url)
    
    Some description.
    """)

    result = Summarizer.summarize(root)
    assert result.name == "My Project"
  end

  test "truncates long descriptions", %{root: root} do
    long_text = String.duplicate("word ", 100)

    File.write!(Path.join(root, "README.md"), """
    # Project
    
    #{long_text}
    
    ## End
    """)

    result = Summarizer.summarize(root)
    assert byte_size(result.description) <= 300
  end

  test "extracts name from package.json when no README", %{root: root} do
    File.write!(Path.join(root, "package.json"), """
    {
      "name": "cool-library",
      "description": "A library"
    }
    """)

    result = Summarizer.summarize(root)
    assert result.name == "Cool Library"
  end
end
