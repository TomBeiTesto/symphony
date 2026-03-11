defmodule SymphonyElixir.LocalBoard do
  @moduledoc """
  Built-in local issue board with JSON persistence.

  Stores issues with states, priorities, labels, and projects.
  Supports code-review templates and repository cloning.
  Persists to a JSON file on every mutation so data survives restarts.
  """

  use GenServer

  require Logger

  alias SymphonyElixir.Issue

  @type issue_record :: %{
          id: String.t(),
          identifier: String.t(),
          title: String.t(),
          description: String.t() | nil,
          priority: integer(),
          state: String.t(),
          branch_name: String.t() | nil,
          url: String.t() | nil,
          labels: [String.t()],
          project_id: String.t() | nil,
          product_id: String.t() | nil,
          created_at: String.t(),
          updated_at: String.t()
        }

  @type project_record :: %{
          id: String.t(),
          name: String.t(),
          slug: String.t(),
          path: String.t() | nil,
          repo_url: String.t() | nil,
          description: String.t() | nil,
          created_at: String.t(),
          updated_at: String.t()
        }

  @type feature_status :: String.t()
  # "missing" | "planned" | "in_progress" | "done" | "n_a"

  @type feature :: %{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          statuses: %{String.t() => feature_status()}
        }

  @type product :: %{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          project_ids: [String.t()],
          features: [feature()],
          created_at: String.t(),
          updated_at: String.t()
        }

  @default_states ["Backlog", "Todo", "In Progress", "Review", "Done", "Archived", "Cancelled"]
  @default_store_path "local_board.json"

  defstruct issues: %{},
            projects: %{},
            products: %{},
            states: @default_states,
            next_number: 1,
            project_prefix: "SYM",
            store_path: @default_store_path

  # --- Built-in Code Review Templates ---

  @templates [
    %{
      id: "code-review",
      name: "Code Review",
      title: "Review: ",
      description:
        "## Code Review\n\n**PR/Branch:** \n**Author:** \n\n### Checklist\n- [ ] Code compiles without warnings\n- [ ] Tests pass\n- [ ] No security vulnerabilities introduced\n- [ ] Code style follows project conventions\n- [ ] Documentation updated if needed\n- [ ] Edge cases handled\n- [ ] Error handling is appropriate\n\n### Notes\n",
      labels: ["code-review"],
      priority: 2
    },
    %{
      id: "bug-report",
      name: "Bug Report",
      title: "Bug: ",
      description:
        "## Bug Report\n\n**Environment:** \n**Version:** \n\n### Steps to Reproduce\n1. \n2. \n3. \n\n### Expected Behavior\n\n\n### Actual Behavior\n\n\n### Screenshots/Logs\n",
      labels: ["bug"],
      priority: 1
    },
    %{
      id: "feature-request",
      name: "Feature Request",
      title: "",
      description:
        "## Feature Request\n\n### Problem Statement\n\n\n### Proposed Solution\n\n\n### Alternatives Considered\n\n\n### Acceptance Criteria\n- [ ] \n- [ ] \n- [ ] \n",
      labels: ["feature"],
      priority: 3
    },
    %{
      id: "security-review",
      name: "Security Review",
      title: "Security: ",
      description:
        "## Security Review\n\n**Component:** \n**Risk Level:** \n\n### Checklist\n- [ ] Input validation reviewed\n- [ ] Authentication/authorization checked\n- [ ] No secrets in source code\n- [ ] SQL injection prevention verified\n- [ ] XSS prevention verified\n- [ ] CSRF protection in place\n- [ ] Dependencies checked for known vulnerabilities\n- [ ] Logging does not expose sensitive data\n\n### Findings\n",
      labels: ["security", "code-review"],
      priority: 1
    },
    %{
      id: "tech-debt",
      name: "Tech Debt",
      title: "Refactor: ",
      description:
        "## Technical Debt\n\n**Area:** \n**Effort Estimate:** \n\n### Current State\n\n\n### Desired State\n\n\n### Migration Plan\n1. \n2. \n3. \n\n### Risks\n",
      labels: ["tech-debt"],
      priority: 4
    },
    %{
      id: "research",
      name: "Research Task",
      title: "Research: ",
      description:
        "## Research Task\n\n**Topic:** \n**Scope:** \n\n### Questions to Answer\n1. \n2. \n3. \n\n### Expected Output\nA report saved to `reports/<identifier>.md` in the workspace.\n\n### Context\n",
      labels: ["research"],
      priority: 3
    }
  ]

  # --- Client API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec list_issues() :: [issue_record()]
  def list_issues do
    GenServer.call(__MODULE__, :list_issues)
  end

  @spec list_issues_by_states([String.t()]) :: [issue_record()]
  def list_issues_by_states(state_names) do
    GenServer.call(__MODULE__, {:list_issues_by_states, state_names})
  end

  @spec get_issue(String.t()) :: {:ok, issue_record()} | {:error, :not_found}
  def get_issue(id) do
    GenServer.call(__MODULE__, {:get_issue, id})
  end

  @spec get_issues_by_ids([String.t()]) :: [issue_record()]
  def get_issues_by_ids(ids) do
    GenServer.call(__MODULE__, {:get_issues_by_ids, ids})
  end

  @spec create_issue(map()) :: {:ok, issue_record()}
  def create_issue(attrs) do
    GenServer.call(__MODULE__, {:create_issue, attrs})
  end

  @spec update_issue(String.t(), map()) :: {:ok, issue_record()} | {:error, :not_found}
  def update_issue(id, attrs) do
    GenServer.call(__MODULE__, {:update_issue, id, attrs})
  end

  @spec move_issue(String.t(), String.t()) :: {:ok, issue_record()} | {:error, :not_found}
  def move_issue(id, new_state) do
    GenServer.call(__MODULE__, {:move_issue, id, new_state})
  end

  @spec delete_issue(String.t()) :: :ok | {:error, :not_found}
  def delete_issue(id) do
    GenServer.call(__MODULE__, {:delete_issue, id})
  end

  @doc "Save agent run data (event_log, result_text, tokens) on a completed issue."
  @spec save_agent_run(String.t(), map()) :: :ok | {:error, :not_found}
  def save_agent_run(issue_id, run_data) do
    GenServer.call(__MODULE__, {:save_agent_run, issue_id, run_data})
  end

  @spec list_states() :: [String.t()]
  def list_states do
    GenServer.call(__MODULE__, :list_states)
  end

  @spec get_board_snapshot() :: map()
  def get_board_snapshot do
    GenServer.call(__MODULE__, :get_board_snapshot)
  end

  # --- Project API ---

  @spec list_projects() :: [project_record()]
  def list_projects do
    GenServer.call(__MODULE__, :list_projects)
  end

  @spec get_project(String.t()) :: {:ok, project_record()} | {:error, :not_found}
  def get_project(id) do
    GenServer.call(__MODULE__, {:get_project, id})
  end

  @spec create_project(map()) :: {:ok, project_record()}
  def create_project(attrs) do
    GenServer.call(__MODULE__, {:create_project, attrs})
  end

  @spec update_project(String.t(), map()) :: {:ok, project_record()} | {:error, :not_found}
  def update_project(id, attrs) do
    GenServer.call(__MODULE__, {:update_project, id, attrs})
  end

  @spec delete_project(String.t()) :: :ok | {:error, :not_found}
  def delete_project(id) do
    GenServer.call(__MODULE__, {:delete_project, id})
  end

  @doc "Clone (or validate) the repository for a project. Returns `{:ok, path}` or `{:error, reason}`."
  @spec clone_project_repo(String.t()) :: {:ok, String.t()} | {:error, term()}
  def clone_project_repo(id) do
    GenServer.call(__MODULE__, {:clone_project_repo, id}, 120_000)
  end

  # --- Template API ---

  @spec list_templates() :: [map()]
  def list_templates do
    @templates
  end

  @spec get_template(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_template(id) do
    case Enum.find(@templates, &(&1.id == id)) do
      nil -> {:error, :not_found}
      tmpl -> {:ok, tmpl}
    end
  end

  # --- Product API ---

  @spec list_products() :: [product()]
  def list_products do
    GenServer.call(__MODULE__, :list_products)
  end

  @spec get_product(String.t()) :: {:ok, product()} | {:error, :not_found}
  def get_product(id) do
    GenServer.call(__MODULE__, {:get_product, id})
  end

  @spec create_product(map()) :: {:ok, product()}
  def create_product(attrs) do
    GenServer.call(__MODULE__, {:create_product, attrs})
  end

  @spec update_product(String.t(), map()) :: {:ok, product()} | {:error, :not_found}
  def update_product(id, attrs) do
    GenServer.call(__MODULE__, {:update_product, id, attrs})
  end

  @spec delete_product(String.t()) :: :ok | {:error, :not_found}
  def delete_product(id) do
    GenServer.call(__MODULE__, {:delete_product, id})
  end

  @spec add_product_feature(String.t(), map()) :: {:ok, product()} | {:error, :not_found}
  def add_product_feature(product_id, feature_attrs) do
    GenServer.call(__MODULE__, {:add_product_feature, product_id, feature_attrs})
  end

  @spec update_product_feature(String.t(), String.t(), map()) ::
          {:ok, product()} | {:error, :not_found}
  def update_product_feature(product_id, feature_id, attrs) do
    GenServer.call(
      __MODULE__,
      {:update_product_feature, product_id, feature_id, attrs}
    )
  end

  @spec delete_product_feature(String.t(), String.t()) ::
          {:ok, product()} | {:error, :not_found}
  def delete_product_feature(product_id, feature_id) do
    GenServer.call(__MODULE__, {:delete_product_feature, product_id, feature_id})
  end

  @spec set_feature_status(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, product()} | {:error, :not_found}
  def set_feature_status(product_id, feature_id, project_id, status) do
    GenServer.call(
      __MODULE__,
      {:set_feature_status, product_id, feature_id, project_id, status}
    )
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    store_path = Keyword.get(opts, :store_path, @default_store_path)
    states = Keyword.get(opts, :states, @default_states)
    prefix = Keyword.get(opts, :project_prefix, "SYM")

    board = %__MODULE__{
      store_path: store_path,
      states: states,
      project_prefix: prefix
    }

    board = load_from_disk(board)

    # Persist immediately so any merged-in states are saved to disk
    persist(board)

    Logger.info(
      "LocalBoard started: #{map_size(board.issues)} issues, states=#{inspect(board.states)}"
    )

    {:ok, board}
  end

  @impl true
  def handle_call(:list_issues, _from, board) do
    issues = board.issues |> Map.values() |> sort_issues()
    {:reply, issues, board}
  end

  def handle_call({:list_issues_by_states, state_names}, _from, board) do
    normalized = MapSet.new(state_names, &String.downcase/1)

    issues =
      board.issues
      |> Map.values()
      |> Enum.filter(fn i -> MapSet.member?(normalized, String.downcase(i.state)) end)
      |> sort_issues()

    {:reply, issues, board}
  end

  def handle_call({:get_issue, id}, _from, board) do
    case Map.get(board.issues, id) do
      nil -> {:reply, {:error, :not_found}, board}
      issue -> {:reply, {:ok, issue}, board}
    end
  end

  def handle_call({:get_issues_by_ids, ids}, _from, board) do
    issues =
      ids
      |> Enum.map(&Map.get(board.issues, &1))
      |> Enum.reject(&is_nil/1)

    {:reply, issues, board}
  end

  def handle_call({:create_issue, attrs}, _from, board) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    id = generate_id()
    identifier = "#{board.project_prefix}-#{board.next_number}"

    issue = %{
      id: id,
      identifier: identifier,
      title: Map.get(attrs, "title", "Untitled"),
      description: Map.get(attrs, "description"),
      priority: parse_priority(Map.get(attrs, "priority", 0)),
      state: Map.get(attrs, "state", hd(board.states)),
      branch_name: Map.get(attrs, "branch_name"),
      url: nil,
      labels: parse_labels(Map.get(attrs, "labels", [])),
      project_id: Map.get(attrs, "project_id"),
      product_id: Map.get(attrs, "product_id"),
      parent_issue_id: Map.get(attrs, "parent_issue_id"),
      propose_followups: Map.get(attrs, "propose_followups", true) != false,
      created_at: now,
      updated_at: now
    }

    board = %{
      board
      | issues: Map.put(board.issues, id, issue),
        next_number: board.next_number + 1
    }

    persist(board)

    {:reply, {:ok, issue}, board}
  end

  def handle_call({:update_issue, id, attrs}, _from, board) do
    case Map.get(board.issues, id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      existing ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        updated =
          existing
          |> maybe_update(:title, attrs)
          |> maybe_update(:description, attrs)
          |> maybe_update(:priority, attrs, &parse_priority/1)
          |> maybe_update(:state, attrs)
          |> maybe_update(:branch_name, attrs)
          |> maybe_update(:labels, attrs, &parse_labels/1)
          |> maybe_update(:propose_followups, attrs, &parse_boolean/1)
          |> Map.put(:updated_at, now)

        board = %{board | issues: Map.put(board.issues, id, updated)}
        persist(board)

        {:reply, {:ok, updated}, board}
    end
  end

  def handle_call({:move_issue, id, new_state}, _from, board) do
    case Map.get(board.issues, id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      existing ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()
        updated = %{existing | state: new_state, updated_at: now}
        board = %{board | issues: Map.put(board.issues, id, updated)}
        persist(board)

        {:reply, {:ok, updated}, board}
    end
  end

  def handle_call({:delete_issue, id}, _from, board) do
    if Map.has_key?(board.issues, id) do
      board = %{board | issues: Map.delete(board.issues, id)}
      persist(board)
      {:reply, :ok, board}
    else
      {:reply, {:error, :not_found}, board}
    end
  end

  def handle_call({:save_agent_run, issue_id, run_data}, _from, board) do
    case Map.get(board.issues, issue_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      issue ->
        updated = Map.put(issue, :agent_run, run_data)
        board = %{board | issues: Map.put(board.issues, issue_id, updated)}
        persist(board)
        {:reply, :ok, board}
    end
  end

  def handle_call(:list_states, _from, board) do
    {:reply, board.states, board}
  end

  def handle_call(:get_board_snapshot, _from, board) do
    columns =
      Enum.map(board.states, fn state ->
        issues =
          board.issues
          |> Map.values()
          |> Enum.filter(fn i -> i.state == state end)
          |> sort_issues()

        %{state: state, issues: issues}
      end)

    snapshot = %{
      states: board.states,
      columns: columns,
      total_issues: map_size(board.issues),
      project_prefix: board.project_prefix,
      projects: Map.values(board.projects)
    }

    {:reply, snapshot, board}
  end

  # --- Project Callbacks ---

  def handle_call(:list_projects, _from, board) do
    projects = board.projects |> Map.values() |> Enum.sort_by(& &1.name)
    {:reply, projects, board}
  end

  def handle_call({:get_project, id}, _from, board) do
    case Map.get(board.projects, id) do
      nil -> {:reply, {:error, :not_found}, board}
      project -> {:reply, {:ok, project}, board}
    end
  end

  def handle_call({:create_project, attrs}, _from, board) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    id = generate_id()
    name = Map.get(attrs, "name", "Untitled Project")
    slug = Map.get(attrs, "slug") || slugify(name)

    project = %{
      id: id,
      name: name,
      slug: slug,
      path: Map.get(attrs, "path"),
      repo_url: Map.get(attrs, "repo_url"),
      description: Map.get(attrs, "description"),
      created_at: now,
      updated_at: now
    }

    board = %{board | projects: Map.put(board.projects, id, project)}
    persist(board)

    {:reply, {:ok, project}, board}
  end

  def handle_call({:update_project, id, attrs}, _from, board) do
    case Map.get(board.projects, id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      existing ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        updated =
          existing
          |> maybe_update(:name, attrs)
          |> maybe_update(:slug, attrs)
          |> maybe_update(:path, attrs)
          |> maybe_update(:repo_url, attrs)
          |> maybe_update(:description, attrs)
          |> Map.put(:updated_at, now)

        board = %{board | projects: Map.put(board.projects, id, updated)}
        persist(board)

        {:reply, {:ok, updated}, board}
    end
  end

  def handle_call({:delete_project, id}, _from, board) do
    if Map.has_key?(board.projects, id) do
      # Cascade: delete all issues belonging to this project
      issues =
        board.issues
        |> Enum.reject(fn {_id, issue} -> issue.project_id == id end)
        |> Map.new()

      board = %{board | projects: Map.delete(board.projects, id), issues: issues}
      persist(board)
      {:reply, :ok, board}
    else
      {:reply, {:error, :not_found}, board}
    end
  end

  def handle_call({:clone_project_repo, id}, _from, board) do
    case Map.get(board.projects, id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      %{repo_url: nil} ->
        {:reply, {:error, :no_repo_url}, board}

      %{repo_url: ""} ->
        {:reply, {:error, :no_repo_url}, board}

      project ->
        result = do_clone(project)

        case result do
          {:ok, clone_path} ->
            now = DateTime.utc_now() |> DateTime.to_iso8601()
            updated = %{project | path: clone_path, updated_at: now}
            board = %{board | projects: Map.put(board.projects, id, updated)}
            persist(board)
            {:reply, {:ok, clone_path}, board}

          {:error, _} = err ->
            {:reply, err, board}
        end
    end
  end

  # --- Product Callbacks ---

  def handle_call(:list_products, _from, board) do
    products = board.products |> Map.values() |> Enum.sort_by(& &1.name)
    {:reply, products, board}
  end

  def handle_call({:get_product, id}, _from, board) do
    case Map.get(board.products, id) do
      nil -> {:reply, {:error, :not_found}, board}
      prod -> {:reply, {:ok, prod}, board}
    end
  end

  def handle_call({:create_product, attrs}, _from, board) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    id = generate_id()

    prod = %{
      id: id,
      name: Map.get(attrs, "name", "Untitled Product"),
      description: Map.get(attrs, "description"),
      project_ids: Map.get(attrs, "project_ids", []),
      features: [],
      created_at: now,
      updated_at: now
    }

    board = %{board | products: Map.put(board.products, id, prod)}
    persist(board)
    {:reply, {:ok, prod}, board}
  end

  def handle_call({:update_product, id, attrs}, _from, board) do
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
          |> Map.put(:updated_at, now)

        board = %{board | products: Map.put(board.products, id, updated)}
        persist(board)
        {:reply, {:ok, updated}, board}
    end
  end

  def handle_call({:delete_product, id}, _from, board) do
    if Map.has_key?(board.products, id) do
      board = %{board | products: Map.delete(board.products, id)}
      persist(board)
      {:reply, :ok, board}
    else
      {:reply, {:error, :not_found}, board}
    end
  end

  def handle_call({:add_product_feature, prod_id, feature_attrs}, _from, board) do
    case Map.get(board.products, prod_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      prod ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()
        feature_id = generate_id()

        # Initialize statuses for all projects as "missing"
        statuses =
          Map.new(prod.project_ids, fn pid -> {pid, "missing"} end)

        feature = %{
          id: feature_id,
          name: Map.get(feature_attrs, "name", "Untitled Feature"),
          description: Map.get(feature_attrs, "description"),
          statuses: Map.merge(statuses, Map.get(feature_attrs, "statuses", %{}))
        }

        updated = %{prod | features: prod.features ++ [feature], updated_at: now}
        board = %{board | products: Map.put(board.products, prod_id, updated)}
        persist(board)
        {:reply, {:ok, updated}, board}
    end
  end

  def handle_call({:update_product_feature, prod_id, feature_id, attrs}, _from, board) do
    case Map.get(board.products, prod_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      prod ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        features =
          Enum.map(prod.features, fn f ->
            if f.id == feature_id do
              f
              |> maybe_update(:name, attrs)
              |> maybe_update(:description, attrs)
            else
              f
            end
          end)

        updated = %{prod | features: features, updated_at: now}
        board = %{board | products: Map.put(board.products, prod_id, updated)}
        persist(board)
        {:reply, {:ok, updated}, board}
    end
  end

  def handle_call({:delete_product_feature, prod_id, feature_id}, _from, board) do
    case Map.get(board.products, prod_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      prod ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()
        features = Enum.reject(prod.features, &(&1.id == feature_id))
        updated = %{prod | features: features, updated_at: now}
        board = %{board | products: Map.put(board.products, prod_id, updated)}
        persist(board)
        {:reply, {:ok, updated}, board}
    end
  end

  def handle_call({:set_feature_status, prod_id, feature_id, project_id, status}, _from, board) do
    case Map.get(board.products, prod_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      prod ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        features =
          Enum.map(prod.features, fn f ->
            if f.id == feature_id do
              %{f | statuses: Map.put(f.statuses, project_id, status)}
            else
              f
            end
          end)

        updated = %{prod | features: features, updated_at: now}
        board = %{board | products: Map.put(board.products, prod_id, updated)}
        persist(board)
        {:reply, {:ok, updated}, board}
    end
  end

  # Ensure any new default states are inserted in the correct position.
  # Persisted states take priority; missing defaults are spliced in
  # just before the state that follows them in the defaults list.
  defp merge_states(persisted, defaults) do
    missing = defaults -- persisted

    Enum.reduce(missing, persisted, fn state, acc ->
      idx = Enum.find_index(defaults, &(&1 == state))
      # Find the next default state that already exists in acc
      insert_before =
        defaults
        |> Enum.drop(idx + 1)
        |> Enum.find(&(&1 in acc))

      case insert_before do
        nil -> acc ++ [state]
        anchor -> List.insert_at(acc, Enum.find_index(acc, &(&1 == anchor)), state)
      end
    end)
  end

  # --- Persistence ---

  defp persist(%__MODULE__{} = board) do
    data = %{
      "issues" => Map.values(board.issues) |> Enum.map(&issue_to_json/1),
      "projects" => Map.values(board.projects) |> Enum.map(&project_to_json/1),
      "products" => Map.values(board.products) |> Enum.map(&product_to_json/1),
      "states" => board.states,
      "next_number" => board.next_number,
      "project_prefix" => board.project_prefix
    }

    json = Jason.encode!(data, pretty: true)
    File.write!(board.store_path, json)
  end

  defp load_from_disk(%__MODULE__{} = board) do
    case File.read(board.store_path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, data} ->
            issues_list = Map.get(data, "issues", [])

            issues =
              Map.new(issues_list, fn raw ->
                issue = json_to_issue(raw)
                {issue.id, issue}
              end)

            max_number =
              issues_list
              |> Enum.map(fn raw ->
                id_str = Map.get(raw, "identifier", "X-0")

                case String.split(id_str, "-") |> List.last() |> Integer.parse() do
                  {n, ""} -> n
                  _ -> 0
                end
              end)
              |> Enum.max(fn -> 0 end)

            projects_list = Map.get(data, "projects", [])

            projects =
              Map.new(projects_list, fn raw ->
                project = json_to_project(raw)
                {project.id, project}
              end)

            # Support legacy "compositions" key for backward compatibility
            products_list = Map.get(data, "products", Map.get(data, "compositions", []))

            products =
              Map.new(products_list, fn raw ->
                prod = json_to_product(raw)
                {prod.id, prod}
              end)

            %{
              board
              | issues: issues,
                projects: projects,
                products: products,
                states: merge_states(Map.get(data, "states", board.states), @default_states),
                next_number: max(Map.get(data, "next_number", max_number + 1), max_number + 1),
                project_prefix: Map.get(data, "project_prefix", board.project_prefix)
            }

          {:error, _} ->
            Logger.warning("Corrupt board file at #{board.store_path}, starting fresh")
            board
        end

      {:error, :enoent} ->
        board

      {:error, reason} ->
        Logger.warning("Failed to read #{board.store_path}: #{inspect(reason)}, starting fresh")
        board
    end
  end

  defp issue_to_json(issue) do
    base = %{
      "id" => issue.id,
      "identifier" => issue.identifier,
      "title" => issue.title,
      "description" => issue.description,
      "priority" => issue.priority,
      "state" => issue.state,
      "branch_name" => issue.branch_name,
      "url" => issue.url,
      "labels" => issue.labels,
      "project_id" => issue[:project_id],
      "product_id" => issue[:product_id],
      "parent_issue_id" => issue[:parent_issue_id],
      "propose_followups" => Map.get(issue, :propose_followups, true),
      "created_at" => issue.created_at,
      "updated_at" => issue.updated_at
    }

    case issue[:agent_run] do
      nil -> base
      run -> Map.put(base, "agent_run", run)
    end
  end

  defp json_to_issue(raw) do
    base = %{
      id: raw["id"],
      identifier: raw["identifier"],
      title: raw["title"],
      description: raw["description"],
      priority: raw["priority"] || 0,
      state: raw["state"] || "Backlog",
      branch_name: raw["branch_name"],
      url: raw["url"],
      labels: raw["labels"] || [],
      project_id: raw["project_id"],
      product_id: raw["product_id"],
      parent_issue_id: raw["parent_issue_id"],
      propose_followups: Map.get(raw, "propose_followups", true) != false,
      created_at: raw["created_at"],
      updated_at: raw["updated_at"]
    }

    case raw["agent_run"] do
      nil -> base
      run -> Map.put(base, :agent_run, run)
    end
  end

  defp project_to_json(project) do
    %{
      "id" => project.id,
      "name" => project.name,
      "slug" => project.slug,
      "path" => project.path,
      "repo_url" => project.repo_url,
      "description" => project.description,
      "created_at" => project.created_at,
      "updated_at" => project.updated_at
    }
  end

  defp json_to_project(raw) do
    %{
      id: raw["id"],
      name: raw["name"],
      slug: raw["slug"],
      path: raw["path"],
      repo_url: raw["repo_url"],
      description: raw["description"],
      created_at: raw["created_at"],
      updated_at: raw["updated_at"]
    }
  end

  defp product_to_json(prod) do
    %{
      "id" => prod.id,
      "name" => prod.name,
      "description" => prod.description,
      "project_ids" => prod.project_ids,
      "features" =>
        Enum.map(prod.features, fn f ->
          %{
            "id" => f.id,
            "name" => f.name,
            "description" => f.description,
            "statuses" => f.statuses
          }
        end),
      "created_at" => prod.created_at,
      "updated_at" => prod.updated_at
    }
  end

  defp json_to_product(raw) do
    %{
      id: raw["id"],
      name: raw["name"],
      description: raw["description"],
      project_ids: raw["project_ids"] || [],
      features:
        Enum.map(raw["features"] || [], fn f ->
          %{
            id: f["id"],
            name: f["name"],
            description: f["description"],
            statuses: f["statuses"] || %{}
          }
        end),
      created_at: raw["created_at"],
      updated_at: raw["updated_at"]
    }
  end

  # --- Conversion to Issue struct (for behaviour compatibility) ---

  @doc "Convert an internal issue record to an `Issue` struct."
  @spec to_issue_struct(issue_record()) :: Issue.t()
  def to_issue_struct(record) do
    %Issue{
      id: record.id,
      identifier: record.identifier,
      title: record.title,
      description: record.description,
      priority: record.priority,
      state: record.state,
      branch_name: record.branch_name,
      url: record.url,
      labels: record.labels || [],
      blocked_by: [],
      project_id: record[:project_id],
      product_id: record[:product_id],
      parent_issue_id: record[:parent_issue_id],
      propose_followups: Map.get(record, :propose_followups, true) != false,
      created_at: parse_dt(record.created_at),
      updated_at: parse_dt(record.updated_at)
    }
  end

  # --- Helpers ---

  defp generate_id do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end

  defp parse_priority(val) when is_integer(val), do: val

  defp parse_priority(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} -> n
      _ -> 0
    end
  end

  defp parse_priority(_), do: 0

  defp parse_labels(val) when is_list(val), do: Enum.map(val, &to_string/1)

  defp parse_labels(val) when is_binary(val),
    do: String.split(val, ",") |> Enum.map(&String.trim/1)

  defp parse_labels(_), do: []

  defp parse_boolean(true), do: true
  defp parse_boolean(false), do: false
  defp parse_boolean("true"), do: true
  defp parse_boolean(_), do: false

  defp sort_issues(issues) do
    Enum.sort_by(issues, fn i -> {-(i.priority || 0), i.created_at || ""} end)
  end

  defp maybe_update(issue, key, attrs) do
    str_key = Atom.to_string(key)

    if Map.has_key?(attrs, str_key) do
      Map.put(issue, key, attrs[str_key])
    else
      issue
    end
  end

  defp maybe_update(issue, key, attrs, transform) do
    str_key = Atom.to_string(key)

    if Map.has_key?(attrs, str_key) do
      Map.put(issue, key, transform.(attrs[str_key]))
    else
      issue
    end
  end

  defp parse_dt(nil), do: nil

  defp parse_dt(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 32)
  end

  defp slugify(_), do: "project"

  defp do_clone(%{repo_url: url, name: name}) do
    target_dir =
      Path.join([
        System.tmp_dir!(),
        "symphony_projects",
        slugify(name) <>
          "_" <> (:crypto.strong_rand_bytes(4) |> Base.url_encode64(padding: false))
      ])

    File.mkdir_p!(Path.dirname(target_dir))

    # Inject git token from Settings if available and URL is HTTPS
    clone_url = inject_git_token(url)

    case System.cmd("git", ["clone", "--depth", "1", clone_url, target_dir],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        Logger.info("Cloned #{url} to #{target_dir}")
        {:ok, target_dir}

      {output, code} ->
        Logger.error("git clone failed (exit #{code}): #{output}")
        {:error, {:clone_failed, output}}
    end
  rescue
    e -> {:error, {:clone_error, Exception.message(e)}}
  end

  defp inject_git_token(url) do
    token = safe_get_setting("git_token")
    provider = safe_get_setting("git_provider")

    if token != "" and String.starts_with?(url, "https://") do
      uri = URI.parse(url)

      userinfo =
        case provider do
          "gitlab" -> "oauth2:#{token}"
          "github" -> "x-access-token:#{token}"
          _ -> "token:#{token}"
        end

      URI.to_string(%{uri | userinfo: userinfo})
    else
      url
    end
  end

  defp safe_get_setting(key) do
    if GenServer.whereis(SymphonyElixir.Settings) do
      SymphonyElixir.Settings.get(key) || ""
    else
      ""
    end
  rescue
    _ -> ""
  end
end
