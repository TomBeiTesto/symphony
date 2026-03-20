defmodule SymphonyElixir.Workflow do
  @moduledoc """
  Parses `WORKFLOW.md` with YAML front matter + Markdown prompt body.
  
  See SPEC Section 5.1–5.5.
  """

  @type t :: %__MODULE__{
          config: map(),
          prompt_template: String.t()
        }

  @enforce_keys [:config, :prompt_template]
  defstruct [:config, :prompt_template]

  @doc """
  Load and parse a workflow file.
  
  Returns `{:ok, workflow}` or `{:error, reason}`.
  """
  @spec load(String.t()) :: {:ok, t()} | {:error, atom() | {atom(), String.t()}}
  def load(path) do
    case File.read(path) do
      {:ok, content} -> parse(content)
      {:error, _} -> {:error, :missing_workflow_file}
    end
  end

  @doc """
  Parse workflow content (YAML front matter + prompt body).
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, atom() | {atom(), String.t()}}
  def parse(content) when is_binary(content) do
    case split_front_matter(content) do
      {:ok, yaml_str, body} ->
        case parse_yaml(yaml_str) do
          {:ok, config} when is_map(config) ->
            {:ok, %__MODULE__{config: config, prompt_template: String.trim(body)}}

          {:ok, _} ->
            {:error, :workflow_front_matter_not_a_map}

          {:error, reason} ->
            {:error, {:workflow_parse_error, reason}}
        end

      :no_front_matter ->
        {:ok, %__MODULE__{config: %{}, prompt_template: String.trim(content)}}
    end
  end

  defp split_front_matter(content) do
    case String.split(content, "\n", parts: 2) do
      ["---" <> _, rest] ->
        case String.split(rest, ~r/\n---\s*\n/, parts: 2) do
          [yaml, body] -> {:ok, yaml, body}
          [yaml] -> {:ok, yaml, ""}
        end

      _ ->
        :no_front_matter
    end
  end

  defp parse_yaml(""), do: {:ok, %{}}

  defp parse_yaml(yaml_str) do
    case YamlElixir.read_from_string(yaml_str) do
      {:ok, result} -> {:ok, result}
      {:error, %{message: msg}} -> {:error, msg}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
