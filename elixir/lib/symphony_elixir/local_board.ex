defmodule SymphonyElixir.LocalBoard do
  @moduledoc """
  Built-in local issue board with JSON persistence.

  Stores issues with states, priorities, labels, and projects.
  Supports code-review templates and repository cloning.
  Persists to a JSON file on every mutation so data survives restarts.
  """

  use GenServer

  require Logger

  alias SymphonyElixir.LocalBoard.{Issues, Projects, Products, Skills, Pipelines, Persistence}

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
          tags: [String.t()],
          created_at: String.t(),
          updated_at: String.t()
        }

  @type feature_status :: String.t()
  # "missing" | "planned" | "in_progress" | "done" | "n_a"

  @type status_history_entry :: %{
          status: feature_status(),
          changed_at: String.t(),
          source: String.t()
        }

  @type feature :: %{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          category: String.t() | nil,
          depends_on: [String.t()],
          statuses: %{String.t() => feature_status()},
          status_history: [status_history_entry()]
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

  @type skill_record :: %{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          content: String.t(),
          category: String.t(),
          tags: [String.t()],
          built_in: boolean(),
          created_at: String.t(),
          updated_at: String.t()
        }

  @type skill_group_record :: %{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          skill_ids: [String.t()],
          created_at: String.t(),
          updated_at: String.t()
        }

  @default_states ["Backlog", "Todo", "In Progress", "Review", "Done", "Archived", "Cancelled"]
  @default_store_path "local_board.json"

  defstruct issues: %{},
            projects: %{},
            products: %{},
            skills: %{},
            skill_groups: %{},
            pipelines: %{},
            pipeline_runs: %{},
            states: @default_states,
            next_number: 1,
            project_prefix: "SYM",
            store_path: @default_store_path

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

  @spec set_feature_status(String.t(), String.t(), String.t(), String.t(), String.t()) ::
          {:ok, product()} | {:error, :not_found}
  def set_feature_status(product_id, feature_id, project_id, status, source \\ "manual") do
    GenServer.call(
      __MODULE__,
      {:set_feature_status, product_id, feature_id, project_id, status, source}
    )
  end

  # --- Skills API ---

  @spec list_skills() :: [skill_record()]
  def list_skills do
    GenServer.call(__MODULE__, :list_skills)
  end

  @spec get_skill(String.t()) :: {:ok, skill_record()} | {:error, :not_found}
  def get_skill(id) do
    GenServer.call(__MODULE__, {:get_skill, id})
  end

  @spec get_skills_by_ids([String.t()]) :: [skill_record()]
  def get_skills_by_ids(ids) do
    GenServer.call(__MODULE__, {:get_skills_by_ids, ids})
  end

  @spec create_skill(map()) :: {:ok, skill_record()}
  def create_skill(attrs) do
    GenServer.call(__MODULE__, {:create_skill, attrs})
  end

  @spec update_skill(String.t(), map()) :: {:ok, skill_record()} | {:error, :not_found}
  def update_skill(id, attrs) do
    GenServer.call(__MODULE__, {:update_skill, id, attrs})
  end

  @spec delete_skill(String.t()) :: :ok | {:error, :not_found} | {:error, :built_in}
  def delete_skill(id) do
    GenServer.call(__MODULE__, {:delete_skill, id})
  end

  @spec duplicate_skill(String.t()) :: {:ok, skill_record()} | {:error, :not_found}
  def duplicate_skill(id) do
    GenServer.call(__MODULE__, {:duplicate_skill, id})
  end

  # --- Skill Groups API ---

  @spec list_skill_groups() :: [skill_group_record()]
  def list_skill_groups do
    GenServer.call(__MODULE__, :list_skill_groups)
  end

  @spec get_skill_group(String.t()) :: {:ok, skill_group_record()} | {:error, :not_found}
  def get_skill_group(id) do
    GenServer.call(__MODULE__, {:get_skill_group, id})
  end

  @spec create_skill_group(map()) :: {:ok, skill_group_record()}
  def create_skill_group(attrs) do
    GenServer.call(__MODULE__, {:create_skill_group, attrs})
  end

  @spec update_skill_group(String.t(), map()) ::
          {:ok, skill_group_record()} | {:error, :not_found}
  def update_skill_group(id, attrs) do
    GenServer.call(__MODULE__, {:update_skill_group, id, attrs})
  end

  @spec delete_skill_group(String.t()) :: :ok | {:error, :not_found}
  def delete_skill_group(id) do
    GenServer.call(__MODULE__, {:delete_skill_group, id})
  end

  @doc "Resolve all skill records for an issue, expanding skill groups and deduplicating."
  @spec resolve_issue_skills(map()) :: [skill_record()]
  def resolve_issue_skills(issue) do
    GenServer.call(__MODULE__, {:resolve_issue_skills, issue})
  end

  # --- Backup & Restore ---

  def list_backups do
    GenServer.call(__MODULE__, :list_backups)
  end

  def restore_backup(filename) do
    GenServer.call(__MODULE__, {:restore_backup, filename})
  end

  # --- Pipeline API ---

  def list_pipelines do
    GenServer.call(__MODULE__, :list_pipelines)
  end

  def get_pipeline(id) do
    GenServer.call(__MODULE__, {:get_pipeline, id})
  end

  def create_pipeline(attrs) do
    GenServer.call(__MODULE__, {:create_pipeline, attrs})
  end

  def update_pipeline(id, attrs) do
    GenServer.call(__MODULE__, {:update_pipeline, id, attrs})
  end

  def delete_pipeline(id) do
    GenServer.call(__MODULE__, {:delete_pipeline, id})
  end

  # --- Pipeline Run API ---

  def create_pipeline_run(pipeline_id) do
    GenServer.call(__MODULE__, {:create_pipeline_run, pipeline_id})
  end

  def get_pipeline_run(pipeline_id, run_id) do
    GenServer.call(__MODULE__, {:get_pipeline_run, pipeline_id, run_id})
  end

  def update_pipeline_run_status(run_id, status) do
    GenServer.call(__MODULE__, {:update_pipeline_run_status, run_id, status})
  end

  def update_node_state(run_id, node_id, state) do
    GenServer.call(__MODULE__, {:update_node_state, run_id, node_id, state})
  end

  def record_gate_decision(run_id, node_id, action, feedback \\ nil) do
    GenServer.call(__MODULE__, {:record_gate_decision, run_id, node_id, action, feedback})
  end

  def list_pipeline_runs(pipeline_id) do
    GenServer.call(__MODULE__, {:list_pipeline_runs, pipeline_id})
  end

  def list_all_active_runs do
    GenServer.call(__MODULE__, :list_all_active_runs)
  end

  # --- Conversion to Issue struct (delegated) ---

  @doc "Convert an internal issue record to an `Issue` struct."
  @spec to_issue_struct(issue_record()) :: SymphonyElixir.Issue.t()
  defdelegate to_issue_struct(record), to: Issues

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

    board = Persistence.load_from_disk(board)

    # Persist immediately so any merged-in states are saved to disk
    Persistence.persist(board)

    Logger.info(
      "LocalBoard started: #{map_size(board.issues)} issues, states=#{inspect(board.states)}"
    )

    {:ok, board}
  end

  # --- Issue Callbacks ---

  @impl true
  def handle_call(:list_issues, _from, board), do: Issues.list_issues(board)

  def handle_call({:list_issues_by_states, state_names}, _from, board),
    do: Issues.list_issues_by_states(board, state_names)

  def handle_call({:get_issue, id}, _from, board), do: Issues.get_issue(board, id)

  def handle_call({:get_issues_by_ids, ids}, _from, board),
    do: Issues.get_issues_by_ids(board, ids)

  def handle_call({:create_issue, attrs}, _from, board), do: Issues.create_issue(board, attrs)

  def handle_call({:update_issue, id, attrs}, _from, board),
    do: Issues.update_issue(board, id, attrs)

  def handle_call({:move_issue, id, new_state}, _from, board),
    do: Issues.move_issue(board, id, new_state)

  def handle_call({:delete_issue, id}, _from, board), do: Issues.delete_issue(board, id)

  def handle_call({:save_agent_run, issue_id, run_data}, _from, board),
    do: Issues.save_agent_run(board, issue_id, run_data)

  def handle_call(:list_states, _from, board), do: Issues.list_states(board)

  def handle_call(:get_board_snapshot, _from, board), do: Issues.get_board_snapshot(board)

  # --- Project Callbacks ---

  def handle_call(:list_projects, _from, board), do: Projects.list_projects(board)

  def handle_call({:get_project, id}, _from, board), do: Projects.get_project(board, id)

  def handle_call({:create_project, attrs}, _from, board),
    do: Projects.create_project(board, attrs)

  def handle_call({:update_project, id, attrs}, _from, board),
    do: Projects.update_project(board, id, attrs)

  def handle_call({:delete_project, id}, _from, board), do: Projects.delete_project(board, id)

  def handle_call({:clone_project_repo, id}, _from, board),
    do: Projects.clone_project_repo(board, id)

  # --- Product Callbacks ---

  def handle_call(:list_products, _from, board), do: Products.list_products(board)

  def handle_call({:get_product, id}, _from, board), do: Products.get_product(board, id)

  def handle_call({:create_product, attrs}, _from, board),
    do: Products.create_product(board, attrs)

  def handle_call({:update_product, id, attrs}, _from, board),
    do: Products.update_product(board, id, attrs)

  def handle_call({:delete_product, id}, _from, board), do: Products.delete_product(board, id)

  def handle_call({:add_product_feature, prod_id, feature_attrs}, _from, board),
    do: Products.add_product_feature(board, prod_id, feature_attrs)

  def handle_call({:update_product_feature, prod_id, feature_id, attrs}, _from, board),
    do: Products.update_product_feature(board, prod_id, feature_id, attrs)

  def handle_call({:delete_product_feature, prod_id, feature_id}, _from, board),
    do: Products.delete_product_feature(board, prod_id, feature_id)

  def handle_call({:set_feature_status, prod_id, feature_id, project_id, status, source}, _from, board),
    do: Products.set_feature_status(board, prod_id, feature_id, project_id, status, source)

  # --- Skills Callbacks ---

  def handle_call(:list_skills, _from, board), do: Skills.list_skills(board)

  def handle_call({:get_skill, id}, _from, board), do: Skills.get_skill(board, id)

  def handle_call({:get_skills_by_ids, ids}, _from, board),
    do: Skills.get_skills_by_ids(board, ids)

  def handle_call({:create_skill, attrs}, _from, board), do: Skills.create_skill(board, attrs)

  def handle_call({:update_skill, id, attrs}, _from, board),
    do: Skills.update_skill(board, id, attrs)

  def handle_call({:delete_skill, id}, _from, board), do: Skills.delete_skill(board, id)

  def handle_call({:duplicate_skill, id}, _from, board), do: Skills.duplicate_skill(board, id)

  # --- Skill Groups Callbacks ---

  def handle_call(:list_skill_groups, _from, board), do: Skills.list_skill_groups(board)

  def handle_call({:get_skill_group, id}, _from, board), do: Skills.get_skill_group(board, id)

  def handle_call({:create_skill_group, attrs}, _from, board),
    do: Skills.create_skill_group(board, attrs)

  def handle_call({:update_skill_group, id, attrs}, _from, board),
    do: Skills.update_skill_group(board, id, attrs)

  def handle_call({:delete_skill_group, id}, _from, board),
    do: Skills.delete_skill_group(board, id)

  def handle_call({:resolve_issue_skills, issue}, _from, board),
    do: Skills.resolve_issue_skills(board, issue)

  # --- Backup & Restore Callbacks ---

  def handle_call(:list_backups, _from, board) do
    backups = Persistence.list_backups(board.store_path)
    {:reply, backups, board}
  end

  def handle_call({:restore_backup, filename}, _from, board) do
    case Persistence.restore_backup(board, filename) do
      {:ok, restored_board} ->
        Logger.info("Board restored from backup: #{filename}")
        {:reply, {:ok, restored_board}, restored_board}

      {:error, reason} ->
        {:reply, {:error, reason}, board}
    end
  end

  # --- Pipeline Callbacks ---

  def handle_call(:list_pipelines, _from, board), do: Pipelines.list_pipelines(board)

  def handle_call({:get_pipeline, id}, _from, board), do: Pipelines.get_pipeline(board, id)

  def handle_call({:create_pipeline, attrs}, _from, board),
    do: Pipelines.create_pipeline(board, attrs)

  def handle_call({:update_pipeline, id, attrs}, _from, board),
    do: Pipelines.update_pipeline(board, id, attrs)

  def handle_call({:delete_pipeline, id}, _from, board), do: Pipelines.delete_pipeline(board, id)

  # --- Pipeline Run Callbacks ---

  def handle_call({:create_pipeline_run, pipeline_id}, _from, board),
    do: Pipelines.create_pipeline_run(board, pipeline_id)

  def handle_call({:get_pipeline_run, pipeline_id, run_id}, _from, board),
    do: Pipelines.get_pipeline_run(board, pipeline_id, run_id)

  def handle_call({:update_pipeline_run_status, run_id, status}, _from, board),
    do: Pipelines.update_pipeline_run_status(board, run_id, status)

  def handle_call({:update_node_state, run_id, node_id, state}, _from, board),
    do: Pipelines.update_node_state(board, run_id, node_id, state)

  def handle_call({:record_gate_decision, run_id, node_id, action, feedback}, _from, board),
    do: Pipelines.record_gate_decision(board, run_id, node_id, action, feedback)

  def handle_call({:list_pipeline_runs, pipeline_id}, _from, board),
    do: Pipelines.list_pipeline_runs(board, pipeline_id)

  def handle_call(:list_all_active_runs, _from, board),
    do: Pipelines.list_all_active_runs(board)

end
