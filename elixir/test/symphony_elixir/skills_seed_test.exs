defmodule SymphonyElixir.SkillsSeedTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.{LocalBoard, SkillsSeed}

  @store_path "test_skills_seed_#{System.unique_integer([:positive])}.json"

  # 10 general + 5 extraction + 22 hardening + 1 summary + 7 feature = 45
  @expected_skill_names [
    # General (merged)
    "verification",
    "systematic-debugging",
    "test-driven-development",
    "plan-and-execute",
    "code-review",
    "scope-discipline",
    "evidence-based-work",
    "structured-reporting",
    "information-design",
    "ui-design",
    # Extraction
    "extract-architecture",
    "extract-business-logic",
    "extract-constraints",
    "extract-workflows",
    "extract-product-overview",
    # Hardening scan/apply pairs
    "hardening-lint-format-scan",
    "hardening-lint-format-apply",
    "hardening-dead-code-scan",
    "hardening-dead-code-apply",
    "hardening-dependency-audit-scan",
    "hardening-dependency-audit-apply",
    "hardening-security-scan-scan",
    "hardening-security-scan-apply",
    "hardening-dry-analysis-scan",
    "hardening-dry-analysis-apply",
    "hardening-error-handling-scan",
    "hardening-error-handling-apply",
    "hardening-type-safety-scan",
    "hardening-type-safety-apply",
    "hardening-test-style-scan",
    "hardening-test-style-apply",
    "hardening-infrastructure-scan",
    "hardening-infrastructure-apply",
    "hardening-playwright-e2e-scan",
    "hardening-playwright-e2e-apply",
    "hardening-test-coverage-scan",
    "hardening-test-coverage-apply",
    "hardening-pipeline-summary",
    # Feature Implementation
    "feature-kb-context",
    "feature-impact-analysis",
    "feature-constraint-check",
    "feature-implementation-plan",
    "feature-code-implementation",
    "feature-test-verification",
    "feature-docs-changelog"
  ]

  @expected_group_names [
    "Quality Essentials",
    "Full Discipline",
    "Research & Analysis",
    "UI & Design",
    "Documentation",
    "Knowledge Extraction",
    "Product Hardening",
    "Feature Implementation"
  ]

  setup do
    start_supervised!({LocalBoard, store_path: @store_path, project_prefix: "SEED"})
    on_exit(fn -> File.rm(@store_path) end)
    :ok
  end

  describe "seed/0 creates all built-in skills" do
    test "all expected skills exist after seeding" do
      assert :ok = SkillsSeed.seed()

      skills = LocalBoard.list_skills()
      skill_names = Enum.map(skills, & &1.name)

      for name <- @expected_skill_names do
        assert name in skill_names, "Expected skill '#{name}' not found"
      end
    end
  end

  describe "seed/0 creates all default skill groups" do
    test "all expected groups exist after seeding" do
      assert :ok = SkillsSeed.seed()

      groups = LocalBoard.list_skill_groups()
      group_names = Enum.map(groups, & &1.name)

      for name <- @expected_group_names do
        assert name in group_names, "Expected skill group '#{name}' not found"
      end
    end
  end

  describe "seed/0 idempotence" do
    test "running seed twice does not create duplicate skills" do
      assert :ok = SkillsSeed.seed()
      assert :ok = SkillsSeed.seed()

      skills = LocalBoard.list_skills()
      assert length(skills) == length(@expected_skill_names)
    end

    test "running seed twice does not create duplicate groups" do
      assert :ok = SkillsSeed.seed()
      assert :ok = SkillsSeed.seed()

      groups = LocalBoard.list_skill_groups()
      assert length(groups) == length(@expected_group_names)
    end

    test "skill IDs remain stable across multiple seeds" do
      assert :ok = SkillsSeed.seed()
      ids_first = LocalBoard.list_skills() |> Enum.map(& &1.id) |> Enum.sort()

      assert :ok = SkillsSeed.seed()
      ids_second = LocalBoard.list_skills() |> Enum.map(& &1.id) |> Enum.sort()

      assert ids_first == ids_second
    end
  end

  describe "seed/0 skill content" do
    test "all skills have non-empty content" do
      assert :ok = SkillsSeed.seed()

      for skill <- LocalBoard.list_skills() do
        assert is_binary(skill.content) and skill.content != "",
               "Skill '#{skill.name}' has empty content"
      end
    end

    test "all skills are marked as built_in" do
      assert :ok = SkillsSeed.seed()

      for skill <- LocalBoard.list_skills() do
        assert skill.built_in == true, "Skill '#{skill.name}' should be built_in"
      end
    end
  end

  describe "seed/0 skill groups contain correct skill references" do
    test "Quality Essentials group contains correct skills" do
      assert :ok = SkillsSeed.seed()

      group =
        LocalBoard.list_skill_groups()
        |> Enum.find(&(&1.name == "Quality Essentials"))

      assert group != nil
      assert length(group.skill_ids) == 2

      resolved = LocalBoard.get_skills_by_ids(group.skill_ids)
      resolved_names = Enum.map(resolved, & &1.name)

      assert "verification" in resolved_names
      assert "code-review" in resolved_names
    end

    test "Full Discipline group contains correct skills" do
      assert :ok = SkillsSeed.seed()

      group =
        LocalBoard.list_skill_groups()
        |> Enum.find(&(&1.name == "Full Discipline"))

      assert group != nil
      assert length(group.skill_ids) == 5

      resolved = LocalBoard.get_skills_by_ids(group.skill_ids)
      resolved_names = Enum.map(resolved, & &1.name)

      for name <- [
            "verification",
            "systematic-debugging",
            "test-driven-development",
            "plan-and-execute",
            "code-review"
          ] do
        assert name in resolved_names
      end
    end

    test "UI & Design group contains correct skills" do
      assert :ok = SkillsSeed.seed()

      group =
        LocalBoard.list_skill_groups()
        |> Enum.find(&(&1.name == "UI & Design"))

      assert group != nil
      assert length(group.skill_ids) == 2

      resolved = LocalBoard.get_skills_by_ids(group.skill_ids)
      resolved_names = Enum.map(resolved, & &1.name)

      for name <- ["information-design", "ui-design"] do
        assert name in resolved_names
      end
    end
  end

  describe "seed/0 error handling" do
    test "seed returns :ok even when called multiple times rapidly" do
      tasks =
        for _ <- 1..3 do
          Task.async(fn -> SkillsSeed.seed() end)
        end

      results = Task.await_many(tasks, 10_000)

      for result <- results do
        assert result == :ok
      end
    end
  end
end
