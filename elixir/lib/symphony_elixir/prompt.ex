defmodule SymphonyElixir.Prompt do
  @moduledoc """
  Strict Liquid-compatible template rendering for issue prompts.

  See SPEC Section 12.
  """

  require Logger

  @default_prompt "You are working on an issue from the project board."

  @doc """
  Render a workflow prompt template with issue context.

  Returns `{:ok, rendered}` or `{:error, reason}`.
  """
  @spec render(String.t(), SymphonyElixir.Issue.t(), integer() | nil) ::
          {:ok, String.t()} | {:error, {:template_render_error, String.t()}}
  def render(template, %SymphonyElixir.Issue{} = issue, attempt \\ nil) do
    template = if template == "", do: @default_prompt, else: template

    context =
      %{"issue" => SymphonyElixir.Issue.to_template_map(issue)}
      |> maybe_add_attempt(attempt)
      |> maybe_add_project(issue)
      |> maybe_add_product(issue)
      |> maybe_add_blocked_by(issue)
      |> maybe_add_skills(issue)
      |> maybe_add_plan(issue)
      |> maybe_add_vault_context(issue)
      |> maybe_add_rerun_context(issue)

    case Solid.parse(template) do
      {:ok, parsed} ->
        case Solid.render(parsed, context) do
          {:ok, iodata, _warnings} ->
            rendered = IO.iodata_to_binary(iodata)
            {:ok, maybe_append_followup_instructions(rendered, issue)}

          {:ok, iodata} ->
            rendered = IO.iodata_to_binary(iodata)
            {:ok, maybe_append_followup_instructions(rendered, issue)}

          {:error, reason} ->
            {:error, {:template_render_error, inspect(reason)}}
        end

      {:error, reason} ->
        {:error, {:template_parse_error, inspect(reason)}}
    end
  end

  defp maybe_add_attempt(context, nil), do: context
  defp maybe_add_attempt(context, attempt), do: Map.put(context, "attempt", attempt)

  defp maybe_add_project(context, %{project_id: pid}) when is_binary(pid) and pid != "" do
    case safe_get_project(pid) do
      nil -> context
      project -> Map.put(context, "project", project)
    end
  end

  defp maybe_add_project(context, _issue), do: context

  defp maybe_add_product(context, %{product_id: prod_id})
       when is_binary(prod_id) and prod_id != "" do
    case safe_get_product(prod_id) do
      nil ->
        context

      product ->
        projects = resolve_product_projects(product)

        context
        |> Map.put("product", product)
        |> Map.put("product_projects", projects)
    end
  end

  defp maybe_add_product(context, _issue), do: context

  defp maybe_add_blocked_by(context, %{blocked_by: blockers})
       when is_list(blockers) and blockers != [] do
    serialized =
      Enum.map(blockers, fn b ->
        %{
          "id" => Map.get(b, :id),
          "identifier" => Map.get(b, :identifier),
          "state" => Map.get(b, :state)
        }
      end)

    Map.put(context, "blocked_by", serialized)
  end

  defp maybe_add_blocked_by(context, _issue), do: context

  defp safe_get_project(project_id) do
    case SymphonyElixir.LocalBoard.get_project(project_id) do
      {:ok, project} ->
        %{
          "id" => project.id,
          "name" => project.name,
          "slug" => project.slug,
          "path" => project[:path],
          "description" => project[:description]
        }

      _ ->
        nil
    end
  rescue
    e ->
      Logger.warning("Failed to fetch project #{project_id} for prompt: #{Exception.message(e)}")
      nil
  end

  defp safe_get_product(product_id) do
    case SymphonyElixir.LocalBoard.get_product(product_id) do
      {:ok, product} ->
        features =
          Enum.map(product.features || [], fn f ->
            %{
              "id" => f.id,
              "name" => f.name,
              "description" => f[:description],
              "category" => f[:category],
              "depends_on" => Map.get(f, :depends_on, []),
              "statuses" => f.statuses
            }
          end)

        %{
          "id" => product.id,
          "name" => product.name,
          "description" => product[:description],
          "project_ids" => product.project_ids || [],
          "features" => features
        }

      _ ->
        nil
    end
  rescue
    e ->
      Logger.warning("Failed to fetch product #{product_id} for prompt: #{Exception.message(e)}")
      nil
  end

  defp resolve_product_projects(product) do
    project_ids = product["project_ids"] || []

    Enum.flat_map(project_ids, fn pid ->
      case safe_get_project(pid) do
        nil ->
          []

        proj ->
          # Add container_path for sandbox mode: extra projects mount at /projects/<basename>
          container_path =
            case proj["path"] do
              p when is_binary(p) and p != "" -> "/projects/#{Path.basename(p)}"
              _ -> nil
            end

          [Map.put(proj, "container_path", container_path)]
      end
    end)
  rescue
    e ->
      Logger.warning("Failed to resolve product projects for prompt: #{Exception.message(e)}")
      []
  end

  defp maybe_add_skills(context, issue) do
    skill_ids = Map.get(issue, :skill_ids, [])
    group_ids = Map.get(issue, :skill_group_ids, [])

    if skill_ids == [] and group_ids == [] do
      context
    else
      skills = safe_resolve_skills(issue)

      if skills == [] do
        context
      else
        rendered_skills =
          skills
          |> Enum.map(fn s ->
            "<skill name=\"#{s.name}\">\n#{s.content}\n</skill>"
          end)
          |> Enum.join("\n\n")

        Map.put(context, "skills", rendered_skills)
      end
    end
  rescue
    e ->
      Logger.warning("Failed to add skills to prompt context: #{Exception.message(e)}")
      context
  end

  defp safe_resolve_skills(issue) do
    if GenServer.whereis(SymphonyElixir.LocalBoard) do
      SymphonyElixir.LocalBoard.resolve_issue_skills(issue)
    else
      []
    end
  rescue
    e ->
      Logger.warning("Failed to resolve skills for prompt: #{Exception.message(e)}")
      []
  end

  defp maybe_append_followup_instructions(rendered, %{propose_followups: true}) do
    rendered <>
      """

      ---
      ## Follow-up Proposals

      After completing your main task, if you identify follow-up work that should be done,
      include a fenced JSON block at the end of your response like this:

      ```follow-ups
      [
        {"title": "Short descriptive title", "description": "What needs to be done and why",
          "labels": ["relevant-label"], "priority": 3}
      ]
      ```

      Only propose follow-ups for genuinely useful work (bugs found, improvements identified,
      missing tests, etc.). Do not propose follow-ups if there is nothing actionable.
      Each follow-up should be a concrete, actionable task — not a vague suggestion.
      """
  end

  defp maybe_append_followup_instructions(rendered, _issue), do: rendered

  defp maybe_add_plan(context, %{plan_status: status, plan_text: text})
       when status == "approved" and is_binary(text) and text != "" do
    context
    |> Map.put("plan", text)
    |> Map.put("execution_phase", true)
  end

  defp maybe_add_plan(context, %{plan_status: "planning"}) do
    Map.put(context, "planning_phase", true)
  end

  defp maybe_add_plan(context, _issue), do: context

  defp maybe_add_vault_context(context, _issue) do
    try do
      kb_type = SymphonyElixir.Settings.get("kb_type") || "local"
      vault_path = SymphonyElixir.Settings.get("kb_vault_path") || ""
      subfolder = SymphonyElixir.Settings.get("kb_subfolder") || "symphony"

      base_path =
        case kb_type do
          "local" when vault_path != "" -> vault_path
          "local" -> SymphonyElixir.Integrations.KnowledgeBase.default_local_path()
          "obsidian" when vault_path != "" -> vault_path
          _ -> nil
        end

      if base_path do
        product_name = get_in(context, ["product", "name"])
        vault_subfolder = if product_name, do: "#{subfolder}/#{product_name}", else: subfolder

        # In sandbox mode, vault is mounted at /vault; otherwise use actual path
        vault_mount = "/vault"

        Map.put(context, "vault", %{
          "path" => vault_mount,
          "actual_path" => base_path,
          "subfolder" => vault_subfolder
        })
      else
        context
      end
    catch
      :exit, _ -> context
    end
  end

  defp maybe_add_rerun_context(context, %{rerun_hint: hint})
       when is_binary(hint) and hint != "" do
    Map.put(context, "rerun_hint", hint)
  end

  defp maybe_add_rerun_context(context, _issue), do: context
end
