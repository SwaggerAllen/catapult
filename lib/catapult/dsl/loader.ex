defmodule Catapult.Dsl.Loader do
  @moduledoc """
  The whole load (`bundle.md`, `chain.md`, `workflow.md`): reads `catapult.yaml` at
  `root`, resolves the dialect, loads the chain bundle and — under a
  dialect that has one — the workflow bundle, and returns every
  problem at once (`Catapult.Config`'s style, applied to the DSL).

  The invariant this module protects and neither bundle loader can see
  alone: **neither axis references the other.** Both `Catapult.Dsl
  .Chain` and `Catapult.Dsl.Workflow` validate only against
  `Catapult.Dsl.SystemStatus`'s platform-fixed vocabulary, never
  against each other's declarations — so there is no compatibility
  pass here beyond confirming each bundle's `kind` matches the
  `catapult.yaml` key that named it (already checked where each loads)
  and that the `runtime` dialect loads no workflow bundle at all.
  """

  alias Catapult.Dsl.CatapultYaml
  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.Dialect
  alias Catapult.Dsl.Registry
  alias Catapult.Dsl.Workflow
  alias Catapult.Dsl.Yaml

  @enforce_keys [:chain]
  defstruct [:chain, :workflow]

  @type t :: %__MODULE__{chain: Chain.t(), workflow: Workflow.t() | nil}

  @doc """
  Loads the bundle pair rooted at `root` (a directory containing
  `catapult.yaml` and `bundles/`).

  Opts:

    * `dialect:` — `"design"` (default) or `"runtime"` (§12).
    * `role_holders:`, `mirror_mapping:` — opt-in workflow checks
      (`Catapult.Dsl.Workflow`'s moduledoc); absent by default.
  """
  @spec load(String.t(), keyword()) ::
          {:ok, t()} | {:error, :catapult_yaml, [String.t()]} | {:error, :bundle, [String.t()]}
  def load(root, opts \\ []) do
    with {:ok, dialect} <- resolve_dialect(opts),
         {:ok, registry} <- Registry.build(dialect.extensions),
         {:ok, catapult_yaml} <- read_catapult_yaml(root, dialect) do
      bundles_root = Path.join(root, "bundles")
      load_axes(bundles_root, catapult_yaml, dialect, registry, opts)
    else
      {:error, problems} -> {:error, :catapult_yaml, problems}
    end
  end

  defp resolve_dialect(opts) do
    name = Keyword.get(opts, :dialect, "design")

    case Dialect.by_name(name) do
      {:ok, dialect} ->
        {:ok, dialect}

      :error ->
        {:error,
         ["dialect #{inspect(name)} is not registered (known: #{inspect(Dialect.names())})"]}
    end
  end

  defp read_catapult_yaml(root, dialect) do
    path = Path.join(root, "catapult.yaml")

    case Yaml.read(path) do
      {:ok, raw} -> CatapultYaml.parse(raw, dialect)
      {:error, reason} -> {:error, [reason]}
    end
  end

  defp load_axes(bundles_root, catapult_yaml, dialect, registry, opts) do
    chain_result = Chain.load(bundles_root, catapult_yaml.chain, registry)
    workflow_result = workflow_result(bundles_root, catapult_yaml.workflow, dialect, opts)

    case {chain_result, workflow_result} do
      {{:ok, chain}, {:ok, workflow}} ->
        {:ok, %__MODULE__{chain: chain, workflow: workflow}}

      {chain_result, workflow_result} ->
        {:error, :bundle, Enum.uniq(problems(chain_result) ++ problems(workflow_result))}
    end
  end

  defp workflow_result(_bundles_root, nil, %Dialect{loads_workflow?: false}, _opts),
    do: {:ok, nil}

  defp workflow_result(bundles_root, name, %Dialect{loads_workflow?: true}, opts) do
    Workflow.load(bundles_root, name, opts)
  end

  defp problems({:ok, _}), do: []
  defp problems({:error, problems}), do: problems
end
