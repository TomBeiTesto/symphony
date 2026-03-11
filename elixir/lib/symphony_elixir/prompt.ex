defmodule SymphonyElixir.Prompt do
  @moduledoc """
  Strict Liquid-compatible template rendering for issue prompts.

  See SPEC Section 12.
  """

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

    case Solid.parse(template) do
      {:ok, parsed} ->
        case Solid.render(parsed, context) do
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
    _ -> nil
  end

  defp safe_get_product(product_id) do
    case SymphonyElixir.LocalBoard.get_product(product_id) do
      {:ok, product} ->
        %{
          "id" => product.id,
          "name" => product.name,
          "description" => product[:description]
        }

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp resolve_product_projects(product) do
    project_ids = product["project_ids"] || []

    Enum.flat_map(project_ids, fn pid ->
      case safe_get_project(pid) do
        nil -> []
        proj -> [proj]
      end
    end)
  rescue
    _ -> []
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
        {"title": "Short descriptive title", "description": "What needs to be done and why", "labels": ["relevant-label"], "priority": 3}
      ]
      ```

      Only propose follow-ups for genuinely useful work (bugs found, improvements identified,
      missing tests, etc.). Do not propose follow-ups if there is nothing actionable.
      Each follow-up should be a concrete, actionable task — not a vague suggestion.
      """
  end

  defp maybe_append_followup_instructions(rendered, _issue), do: rendered
end
