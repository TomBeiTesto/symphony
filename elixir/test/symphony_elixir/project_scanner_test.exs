defmodule SymphonyElixir.ProjectScannerTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.ProjectScanner

  setup do
    tmp = Path.join(System.tmp_dir!(), "scanner_test_#{:rand.uniform(999_999)}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, root: tmp}
  end

  describe "scan/1" do
    test "returns empty list for empty directory", %{root: root} do
      assert {:ok, []} = ProjectScanner.scan(root)
    end

    test "returns error for non-existent path" do
      assert {:error, :not_a_directory} = ProjectScanner.scan("/nonexistent_path_12345")
    end

    test "discovers subdirectories as projects", %{root: root} do
      File.mkdir_p!(Path.join(root, "alpha"))
      File.mkdir_p!(Path.join(root, "beta"))

      assert {:ok, candidates} = ProjectScanner.scan(root)
      assert length(candidates) == 2
      names = Enum.map(candidates, & &1.name)
      assert "Alpha" in names
      assert "Beta" in names
    end

    test "ignores hidden directories", %{root: root} do
      File.mkdir_p!(Path.join(root, ".hidden"))
      File.mkdir_p!(Path.join(root, "visible"))

      assert {:ok, [candidate]} = ProjectScanner.scan(root)
      assert candidate.name == "Visible"
    end

    test "ignores files (only directories)", %{root: root} do
      File.write!(Path.join(root, "not_a_dir.txt"), "hello")
      File.mkdir_p!(Path.join(root, "real_project"))

      assert {:ok, [candidate]} = ProjectScanner.scan(root)
      assert candidate.name == "Real Project"
    end

    test "reads README.md for title and description", %{root: root} do
      proj = Path.join(root, "my-app")
      File.mkdir_p!(proj)

      File.write!(Path.join(proj, "README.md"), """
      # My Awesome App

      This is a great application that does many things.

      ## Installation

      Run `mix deps.get`.
      """)

      assert {:ok, [candidate]} = ProjectScanner.scan(root)
      assert candidate.name == "My Awesome App"
      assert candidate.description =~ "great application"
    end

    test "falls back to humanized dir name without README", %{root: root} do
      File.mkdir_p!(Path.join(root, "my-cool-project"))

      assert {:ok, [candidate]} = ProjectScanner.scan(root)
      assert candidate.name == "My Cool Project"
      assert candidate.slug == "my-cool-project"
      assert candidate.description == nil
    end

    test "sets path to full directory path", %{root: root} do
      File.mkdir_p!(Path.join(root, "service"))

      assert {:ok, [candidate]} = ProjectScanner.scan(root)
      assert String.ends_with?(candidate.path, "service")
    end

    test "detects git remote URL", %{root: root} do
      proj = Path.join(root, "repo")
      git_dir = Path.join(proj, ".git")
      File.mkdir_p!(git_dir)

      File.write!(Path.join(git_dir, "config"), """
      [core]
        bare = false
      [remote "origin"]
        url = https://github.com/user/repo.git
        fetch = +refs/heads/*:refs/remotes/origin/*
      """)

      assert {:ok, [candidate]} = ProjectScanner.scan(root)
      assert candidate.repo_url == "https://github.com/user/repo.git"
    end

    test "repo_url is nil without .git", %{root: root} do
      File.mkdir_p!(Path.join(root, "no-git"))

      assert {:ok, [candidate]} = ProjectScanner.scan(root)
      assert candidate.repo_url == nil
    end

    test "skips badge lines and HTML when extracting description", %{root: root} do
      proj = Path.join(root, "badged")
      File.mkdir_p!(proj)

      File.write!(Path.join(proj, "README.md"), """
      # Badged Project

      [![CI](https://img.shields.io/badge/ci-passing-green)]()
      ![Logo](logo.png)

      The actual description starts here.

      ## More stuff
      """)

      assert {:ok, [candidate]} = ProjectScanner.scan(root)
      assert candidate.description == "The actual description starts here."
    end

    test "truncates long descriptions", %{root: root} do
      proj = Path.join(root, "verbose")
      File.mkdir_p!(proj)

      long_text = String.duplicate("word ", 100)

      File.write!(Path.join(proj, "README.md"), """
      # Verbose Project

      #{long_text}

      ## End
      """)

      assert {:ok, [candidate]} = ProjectScanner.scan(root)
      assert String.length(candidate.description) <= 300
      assert String.ends_with?(candidate.description, "...")
    end

    test "includes git_branch field", %{root: root} do
      File.mkdir_p!(Path.join(root, "project"))

      assert {:ok, [candidate]} = ProjectScanner.scan(root)
      assert Map.has_key?(candidate, :git_branch)
    end

    test "extracts description from package.json when README is missing", %{root: root} do
      proj = Path.join(root, "js-lib")
      File.mkdir_p!(proj)

      File.write!(Path.join(proj, "package.json"), """
      {
        "name": "@scope/js-lib",
        "description": "A JavaScript utility library"
      }
      """)

      assert {:ok, [candidate]} = ProjectScanner.scan(root)
      assert candidate.description == "A JavaScript utility library"
    end

    test "extracts description from About section over first paragraph", %{root: root} do
      proj = Path.join(root, "about-project")
      File.mkdir_p!(proj)

      File.write!(Path.join(proj, "README.md"), """
      # About Project

      [![Build](https://example.com/badge)]()

      Some confusing badges paragraph.

      ## About

      This is the real description from the About section.

      ## Usage
      """)

      assert {:ok, [candidate]} = ProjectScanner.scan(root)
      assert candidate.description =~ "real description from the About section"
    end
  end

  describe "scan/2 with recursive option" do
    test "detects monorepo with apps/ subdirectories", %{root: root} do
      mono = Path.join(root, "monorepo")
      File.mkdir_p!(mono)
      File.write!(Path.join(mono, "package.json"), ~s({"name": "monorepo"}))

      app1 = Path.join([mono, "apps", "frontend"])
      app2 = Path.join([mono, "apps", "backend"])
      File.mkdir_p!(app1)
      File.mkdir_p!(app2)
      File.write!(Path.join(app1, "package.json"), ~s({"name": "frontend", "description": "UI"}))
      File.write!(Path.join(app2, "package.json"), ~s({"name": "backend", "description": "API"}))

      assert {:ok, candidates} = ProjectScanner.scan(root, recursive: true)
      names = Enum.map(candidates, & &1.name)
      # Should find the sub-projects and the root
      assert length(candidates) >= 2
      assert "Frontend" in names or "frontend" in Enum.map(candidates, & &1.slug)
      assert "Backend" in names or "backend" in Enum.map(candidates, & &1.slug)
    end

    test "treats non-monorepo as single project with recursive", %{root: root} do
      proj = Path.join(root, "simple")
      File.mkdir_p!(proj)
      File.write!(Path.join(proj, "mix.exs"), "defmodule MyApp do end")

      assert {:ok, candidates} = ProjectScanner.scan(root, recursive: true)
      assert length(candidates) == 1
      assert hd(candidates).slug == "simple"
    end
  end
end
