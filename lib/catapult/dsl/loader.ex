defmodule Catapult.Dsl.Loader do
  @moduledoc """
  The whole load (`bundle.md`, `chain.md`, `workflow.md`): reads
  `catapult.yaml` at `root`, resolves the dialect, loads the chain
  bundle and — under a dialect that has one — the workflow bundle
  against it, and returns every problem at once (`Catapult.Config`'s
  style, applied to the DSL).

  **The reference runs one way** (`bundle.md` #11): the workflow names
  the chain's tiers and flows, and checks against them at its own load
  time (`Catapult.Dsl.Workflow`'s own cross-axis checks); the chain
  never references the workflow, and its own load never needs one in
  view. So the chain loads first, unconditionally, and only a
  successfully loaded chain is handed to the workflow to check against
  — a chain that fails to load leaves nothing to check the workflow
  against, and is reported alone rather than paired with a workflow
  error that would only restate the same missing tiers and flows.
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
    case Chain.load(bundles_root, catapult_yaml.chain, registry) do
      {:ok, chain} ->
        case workflow_result(bundles_root, catapult_yaml.workflow, chain, dialect, opts) do
          {:ok, workflow} -> {:ok, %__MODULE__{chain: chain, workflow: workflow}}
          {:error, problems} -> {:error, :bundle, Enum.uniq(problems)}
        end

      {:error, chain_problems} ->
        # The workflow axis references the chain (`bundle.md` #11), so
        # a broken chain leaves nothing to check it against — reported
        # alone rather than paired with a workflow error that would
        # only restate the same missing tiers and flows.
        {:error, :bundle, Enum.uniq(chain_problems)}
    end
  end

  defp workflow_result(_bundles_root, nil, _chain, %Dialect{loads_workflow?: false}, _opts),
    do: {:ok, nil}

  defp workflow_result(bundles_root, name, chain, %Dialect{loads_workflow?: true}, opts) do
    Workflow.load(bundles_root, name, chain, opts)
  end
end
