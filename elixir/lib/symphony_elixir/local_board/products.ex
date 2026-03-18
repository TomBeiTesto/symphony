defmodule SymphonyElixir.LocalBoard.Products do
  @moduledoc """
  Product-related operations for the local board.

  Handles CRUD for products and their features, including
  per-project feature status tracking.
  All functions receive and return the board state struct.
  """

  alias SymphonyElixir.LocalBoard.Persistence

  import SymphonyElixir.LocalBoard.Helpers

  @valid_statuses ~w(missing planned in_progress done n_a)

  # Filter depends_on to only include valid feature IDs and prevent circular deps.
  defp validate_depends_on(depends_on, feature_id, features) do
    existing_ids = MapSet.new(features, & &1.id)

    # Filter to only existing feature IDs (excluding self)
    valid_deps =
      depends_on
      |> Enum.filter(fn dep_id ->
        dep_id != feature_id and MapSet.member?(existing_ids, dep_id)
      end)
      |> Enum.uniq()

    # Detect circular dependencies via DFS
    dep_map =
      Map.new(features, fn f ->
        if f.id == feature_id do
          {f.id, valid_deps}
        else
          {f.id, f.depends_on || []}
        end
      end)

    reject_circular(valid_deps, feature_id, dep_map)
  end

  defp reject_circular(deps, target_id, dep_map) do
    Enum.filter(deps, fn dep_id ->
      not creates_cycle?(dep_id, target_id, dep_map, MapSet.new())
    end)
  end

  defp creates_cycle?(current, target, dep_map, visited) do
    cond do
      current == target ->
        true

      MapSet.member?(visited, current) ->
        false

      true ->
        visited = MapSet.put(visited, current)
        transitive_deps = Map.get(dep_map, current, [])
        Enum.any?(transitive_deps, &creates_cycle?(&1, target, dep_map, visited))
    end
  end

  # --- handle_call delegates ---

  def list_products(board) do
    products = board.products |> Map.values() |> Enum.sort_by(& &1.name)
    {:reply, products, board}
  end

  def get_product(board, id) do
    case Map.get(board.products, id) do
      nil -> {:reply, {:error, :not_found}, board}
      prod -> {:reply, {:ok, prod}, board}
    end
  end

  def create_product(board, attrs) do
    name = Map.get(attrs, "name", "Untitled Product") |> String.trim()

    dupe =
      Enum.any?(Map.values(board.products), fn p ->
        String.downcase(String.trim(p.name)) == String.downcase(name)
      end)

    if dupe do
      {:reply, {:error, :duplicate_name}, board}
    else
      now = DateTime.utc_now() |> DateTime.to_iso8601()
      id = generate_id()

      prod = %{
        id: id,
        name: name,
        description: Map.get(attrs, "description"),
        project_ids: Map.get(attrs, "project_ids", []),
        labels: parse_labels(Map.get(attrs, "labels", [])),
        features: [],
        created_at: now,
        updated_at: now
      }

      board = %{board | products: Map.put(board.products, id, prod)}
      Persistence.persist(board)
      {:reply, {:ok, prod}, board}
    end
  end

  def update_product(board, id, attrs) do
    case Map.get(board.products, id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      existing ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        updated =
          existing
          |> maybe_update(:name, attrs)
          |> maybe_update(:description, attrs)
          |> maybe_update(:project_ids, attrs)
          |> maybe_update(:labels, attrs, &parse_labels/1)
          |> Map.put(:updated_at, now)

        # If project_ids changed, clean up feature statuses for removed projects
        updated =
          if Map.has_key?(attrs, "project_ids") do
            new_pids = MapSet.new(updated.project_ids)

            cleaned_features =
              Enum.map(updated.features, fn f ->
                cleaned_statuses =
                  f.statuses
                  |> Enum.filter(fn {pid, _} -> MapSet.member?(new_pids, pid) end)
                  |> Map.new()

                %{f | statuses: cleaned_statuses}
              end)

            %{updated | features: cleaned_features}
          else
            updated
          end

        board = %{board | products: Map.put(board.products, id, updated)}
        Persistence.persist(board)
        {:reply, {:ok, updated}, board}
    end
  end

  def delete_product(board, id) do
    if Map.has_key?(board.products, id) do
      board = %{board | products: Map.delete(board.products, id)}
      Persistence.persist(board)
      {:reply, :ok, board}
    else
      {:reply, {:error, :not_found}, board}
    end
  end

  def add_product_feature(board, prod_id, feature_attrs) do
    case Map.get(board.products, prod_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      prod ->
        feature_name = Map.get(feature_attrs, "name", "Untitled Feature") |> String.trim()
        agent_project_ids = Map.get(feature_attrs, "project_ids", [])
        agent_statuses = Map.get(feature_attrs, "statuses", %{})
        is_manual = agent_project_ids == [] and agent_statuses == %{}

        # Check for duplicate feature name on manual creation
        dupe =
          is_manual and
            Enum.any?(prod.features, fn f ->
              String.downcase(String.trim(f.name)) == String.downcase(feature_name)
            end)

        if dupe do
          {:reply, {:error, :duplicate_name}, board}
        else
          now = DateTime.utc_now() |> DateTime.to_iso8601()
          feature_id = generate_id()
          valid_ids = MapSet.new(prod.project_ids)

          statuses =
            cond do
              agent_project_ids != [] ->
                agent_project_ids
                |> Enum.filter(&MapSet.member?(valid_ids, &1))
                |> Map.new(fn pid ->
                  s = Map.get(agent_statuses, pid, "missing")
                  {pid, if(s in @valid_statuses, do: s, else: "missing")}
                end)

              agent_statuses != %{} ->
                agent_statuses
                |> Enum.filter(fn {pid, _} -> MapSet.member?(valid_ids, pid) end)
                |> Map.new(fn {pid, s} ->
                  {pid, if(s in @valid_statuses, do: s, else: "missing")}
                end)

              true ->
                Map.new(prod.project_ids, fn pid -> {pid, "missing"} end)
            end

          raw_deps = Map.get(feature_attrs, "depends_on", [])
          clean_deps = validate_depends_on(raw_deps, feature_id, prod.features)

          feature = %{
            id: feature_id,
            name: feature_name,
            description: Map.get(feature_attrs, "description"),
            category: Map.get(feature_attrs, "category"),
            depends_on: clean_deps,
            statuses: statuses,
            status_history: []
          }

          updated = %{prod | features: prod.features ++ [feature], updated_at: now}
          board = %{board | products: Map.put(board.products, prod_id, updated)}
          Persistence.persist(board)
          {:reply, {:ok, updated}, board}
        end
    end
  end

  def update_product_feature(board, prod_id, feature_id, attrs) do
    case Map.get(board.products, prod_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      prod ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        features =
          Enum.map(prod.features, fn f ->
            if f.id == feature_id do
              updated_f =
                f
                |> maybe_update(:name, attrs)
                |> maybe_update(:description, attrs)
                |> maybe_update(:category, attrs)
                |> maybe_update(:depends_on, attrs)

              # Validate deps if they were updated
              if Map.has_key?(attrs, "depends_on") do
                clean_deps = validate_depends_on(updated_f.depends_on, feature_id, prod.features)
                %{updated_f | depends_on: clean_deps}
              else
                updated_f
              end
            else
              f
            end
          end)

        updated = %{prod | features: features, updated_at: now}
        board = %{board | products: Map.put(board.products, prod_id, updated)}
        Persistence.persist(board)
        {:reply, {:ok, updated}, board}
    end
  end

  def delete_product_feature(board, prod_id, feature_id) do
    case Map.get(board.products, prod_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      prod ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        features =
          prod.features
          |> Enum.reject(&(&1.id == feature_id))
          # Remove deleted feature from other features' depends_on
          |> Enum.map(fn f ->
            %{f | depends_on: Enum.reject(f.depends_on, &(&1 == feature_id))}
          end)

        updated = %{prod | features: features, updated_at: now}
        board = %{board | products: Map.put(board.products, prod_id, updated)}
        Persistence.persist(board)
        {:reply, {:ok, updated}, board}
    end
  end

  def set_feature_status(board, prod_id, feature_id, project_id, status, source \\ "manual") do
    if status not in @valid_statuses do
      {:reply, {:error, :invalid_status}, board}
    else
      set_feature_status_impl(board, prod_id, feature_id, project_id, status, source)
    end
  end

  defp set_feature_status_impl(board, prod_id, feature_id, project_id, status, source) do
    case Map.get(board.products, prod_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      prod ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        features =
          Enum.map(prod.features, fn f ->
            if f.id == feature_id do
              history_entry = %{
                project_id: project_id,
                status: status,
                changed_at: now,
                source: source
              }

              existing_history = Map.get(f, :status_history, [])

              %{f | statuses: Map.put(f.statuses, project_id, status)}
              |> Map.put(:status_history, [history_entry | existing_history])
            else
              f
            end
          end)

        updated = %{prod | features: features, updated_at: now}
        board = %{board | products: Map.put(board.products, prod_id, updated)}
        Persistence.persist(board)
        {:reply, {:ok, updated}, board}
    end
  end
end
