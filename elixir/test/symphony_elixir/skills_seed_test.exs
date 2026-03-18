defmodule SymphonyElixir.SkillsSeedTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.{LocalBoard, SkillsSeed}

  @store_path "test_skills_seed_#{System.unique_integer([:positive])}.json"

  @expected_skill_names [
    "verification-before-completion",
    "systematic-debugging",
    "test-driven-development",
    "design-before-code",
    "executing-plans",
    "code-review",
    "source-verification",
    "structured-reporting",
    "audience-aware-writing",
    "incremental-verification",
    "scope-discipline",
    "evidence-based-decisions",
    "content-hierarchy",
    "user-journey-first",
    "cognitive-load-budget",
    "spatial-consistency"
  ]

  @expected_group_names [
    "Quality Essentials",
    "Full Discipline",
    "Research & Analysis",
    "UI & Design",
    "Documentation"
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

      assert "verification-before-completion" in resolved_names
      assert "code-review" in resolved_names
    end

    test "Full Discipline group contains correct skills" do
      assert :ok = SkillsSeed.seed()

      group =
        LocalBoard.list_skill_groups()
        |> Enum.find(&(&1.name == "Full Discipline"))

      assert group != nil
      assert length(group.skill_ids) == 6

      resolved = LocalBoard.get_skills_by_ids(group.skill_ids)
      resolved_names = Enum.map(resolved, & &1.name)

      for name <- [
            "verification-before-completion",
            "systematic-debugging",
            "test-driven-development",
            "design-before-code",
            "executing-plans",
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
      assert length(group.skill_ids) == 4

      resolved = LocalBoard.get_skills_by_ids(group.skill_ids)
      resolved_names = Enum.map(resolved, & &1.name)

      for name <- [
            "content-hierarchy",
            "user-journey-first",
            "cognitive-load-budget",
            "spatial-consistency"
          ] do
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
