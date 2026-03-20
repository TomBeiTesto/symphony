defmodule SymphonyElixir.LocalBoard.SkillsTest do
  use SymphonyElixir.BoardCase, project_prefix: "SK"

  alias SymphonyElixir.LocalBoard

  describe "skill CRUD" do
    test "create and list skills" do
      assert LocalBoard.list_skills() == []

      {:ok, skill} =
        LocalBoard.create_skill(%{
          "name" => "TDD",
          "content" => "Write tests first",
          "category" => "quality"
        })

      assert skill.name == "TDD"
      assert skill.content == "Write tests first"
      assert skill.category == "quality"
      assert skill.built_in == false

      skills = LocalBoard.list_skills()
      assert length(skills) == 1
      assert hd(skills).id == skill.id
    end

    test "get skill by id" do
      {:ok, skill} = LocalBoard.create_skill(%{"name" => "Test Skill"})
      assert {:ok, found} = LocalBoard.get_skill(skill.id)
      assert found.id == skill.id

      assert {:error, :not_found} = LocalBoard.get_skill("nonexistent")
    end

    test "get multiple skills by ids" do
      {:ok, s1} = LocalBoard.create_skill(%{"name" => "Skill A"})
      {:ok, s2} = LocalBoard.create_skill(%{"name" => "Skill B"})
      {:ok, _s3} = LocalBoard.create_skill(%{"name" => "Skill C"})

      found = LocalBoard.get_skills_by_ids([s1.id, s2.id, "nonexistent"])
      assert length(found) == 2
      ids = Enum.map(found, & &1.id)
      assert s1.id in ids
      assert s2.id in ids
    end

    test "update skill" do
      {:ok, skill} = LocalBoard.create_skill(%{"name" => "Old Name", "content" => "old"})

      {:ok, updated} = LocalBoard.update_skill(skill.id, %{"name" => "New Name"})
      assert updated.name == "New Name"
      assert updated.content == "old"

      assert {:error, :not_found} = LocalBoard.update_skill("nonexistent", %{"name" => "x"})
    end

    test "delete skill" do
      {:ok, skill} = LocalBoard.create_skill(%{"name" => "Deletable"})
      assert :ok = LocalBoard.delete_skill(skill.id)
      assert {:error, :not_found} = LocalBoard.get_skill(skill.id)
    end

    test "cannot delete built-in skill" do
      {:ok, skill} = LocalBoard.create_skill(%{"name" => "Built-in", "built_in" => true})
      assert {:error, :built_in} = LocalBoard.delete_skill(skill.id)
      assert {:ok, _} = LocalBoard.get_skill(skill.id)
    end

    test "delete skill cascades to skill groups" do
      {:ok, skill} = LocalBoard.create_skill(%{"name" => "Cascade Test"})
      {:ok, group} = LocalBoard.create_skill_group(%{"name" => "Group", "skill_ids" => [skill.id]})

      assert :ok = LocalBoard.delete_skill(skill.id)

      {:ok, updated_group} = LocalBoard.get_skill_group(group.id)
      assert updated_group.skill_ids == []
    end

    test "duplicate skill" do
      {:ok, original} =
        LocalBoard.create_skill(%{
          "name" => "Original",
          "content" => "content here",
          "category" => "quality",
          "built_in" => true
        })

      {:ok, copy} = LocalBoard.duplicate_skill(original.id)
      assert copy.name == "Original (copy)"
      assert copy.content == "content here"
      assert copy.built_in == false
      assert copy.id != original.id

      assert {:error, :not_found} = LocalBoard.duplicate_skill("nonexistent")
    end

    test "create skill with defaults" do
      {:ok, skill} = LocalBoard.create_skill(%{})
      assert skill.name == "Untitled Skill"
      assert skill.content == ""
      assert skill.category == "custom"
      assert skill.built_in == false
    end
  end

  describe "skill group CRUD" do
    test "create and list skill groups" do
      assert LocalBoard.list_skill_groups() == []

      {:ok, group} =
        LocalBoard.create_skill_group(%{
          "name" => "Quality",
          "description" => "Quality skills"
        })

      assert group.name == "Quality"
      groups = LocalBoard.list_skill_groups()
      assert length(groups) == 1
    end

    test "get skill group by id" do
      {:ok, group} = LocalBoard.create_skill_group(%{"name" => "Test Group"})
      assert {:ok, found} = LocalBoard.get_skill_group(group.id)
      assert found.id == group.id

      assert {:error, :not_found} = LocalBoard.get_skill_group("nonexistent")
    end

    test "update skill group" do
      {:ok, group} = LocalBoard.create_skill_group(%{"name" => "Old"})
      {:ok, updated} = LocalBoard.update_skill_group(group.id, %{"name" => "New"})
      assert updated.name == "New"

      assert {:error, :not_found} = LocalBoard.update_skill_group("nonexistent", %{"name" => "x"})
    end

    test "delete skill group" do
      {:ok, group} = LocalBoard.create_skill_group(%{"name" => "Deletable"})
      assert :ok = LocalBoard.delete_skill_group(group.id)
      assert {:error, :not_found} = LocalBoard.get_skill_group(group.id)

      assert {:error, :not_found} = LocalBoard.delete_skill_group("nonexistent")
    end

    test "create skill group with defaults" do
      {:ok, group} = LocalBoard.create_skill_group(%{})
      assert group.name == "Untitled Group"
      assert group.skill_ids == []
    end
  end

  describe "resolve_issue_skills/1" do
    test "resolves direct skill_ids" do
      {:ok, s1} = LocalBoard.create_skill(%{"name" => "A", "category" => "quality"})
      {:ok, s2} = LocalBoard.create_skill(%{"name" => "B", "category" => "quality"})

      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Test",
          "skill_ids" => [s1.id, s2.id]
        })

      skills = LocalBoard.resolve_issue_skills(issue)
      assert length(skills) == 2
    end

    test "resolves skills from skill groups" do
      {:ok, s1} = LocalBoard.create_skill(%{"name" => "Grouped", "category" => "quality"})

      {:ok, group} =
        LocalBoard.create_skill_group(%{"name" => "G", "skill_ids" => [s1.id]})

      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Test",
          "skill_group_ids" => [group.id]
        })

      skills = LocalBoard.resolve_issue_skills(issue)
      assert length(skills) == 1
      assert hd(skills).id == s1.id
    end

    test "deduplicates skills from direct and group references" do
      {:ok, skill} = LocalBoard.create_skill(%{"name" => "Shared", "category" => "quality"})

      {:ok, group} =
        LocalBoard.create_skill_group(%{"name" => "G", "skill_ids" => [skill.id]})

      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Test",
          "skill_ids" => [skill.id],
          "skill_group_ids" => [group.id]
        })

      skills = LocalBoard.resolve_issue_skills(issue)
      assert length(skills) == 1
    end

    test "handles missing group gracefully" do
      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Test",
          "skill_group_ids" => ["nonexistent"]
        })

      skills = LocalBoard.resolve_issue_skills(issue)
      assert skills == []
    end
  end
end
