defmodule Catapult.Dsl do
  @moduledoc """
  The DSL core (`systems/core_dsl.md`): the frozen vocabulary, the
  bundle loader, `extends:` content layering, and the extension
  registry (v5 §9) through which platform extensions grow it. This
  module is the boundary export; `Catapult.Dsl.Loader` and its
  siblings under `lib/catapult/dsl/` carry the implementation.
  """

  use Catapult.Component, slug: :dsl

  alias Catapult.Dsl.Error
  alias Catapult.Dsl.Grammar
  alias Catapult.Dsl.Loader

  @impl Catapult.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-only"]

  @impl Catapult.Component
  def errors do
    [
      {:dsl_catapult_yaml_invalid,
       "catapult.yaml is missing, malformed, or names an axis the active dialect refuses",
       remedy:
         "fix catapult.yaml to name a chain: bundle (and, under the design dialect, a workflow: bundle) under bundles/"},
      {:dsl_bundle_invalid, "a bundle failed load-time validation (dsl-syntax.md §13)",
       remedy:
         "fix every problem in details[:problems] and reload; a bundle that loads is a bundle the engine can run"}
    ]
  end

  @doc """
  Loads the bundle pair rooted at `root` (dsl-syntax.md §1-§15):
  `catapult.yaml` plus its named chain bundle and, under a dialect
  with one, its named workflow bundle. See `Catapult.Dsl.Loader.load/2`
  for `opts`.
  """
  @spec load(String.t(), keyword()) :: {:ok, Loader.t()} | {:error, Error.t()}
  defexport load(root, opts \\ []) do
    case Loader.load(root, opts) do
      {:ok, loaded} ->
        {:ok, loaded}

      {:error, :catapult_yaml, problems} ->
        {:error, Error.new(:dsl_catapult_yaml_invalid, problems: problems)}

      {:error, :bundle, problems} ->
        {:error, Error.new(:dsl_bundle_invalid, problems: problems)}
    end
  end

  @doc """
  Validates `body` against the grammar named by `root_tag` +
  `grammar_path` for `bundle_name` under `bundles_root` (dsl-syntax.md
  §10). See `Catapult.Dsl.Grammar.validate/5`. One validator source:
  generation's commit path and engine's own commit-time rejection call
  this rather than two implementations that could drift
  (`systems/core_dsl.md`).
  """
  @spec validate_draft(String.t(), String.t(), String.t(), String.t(), String.t()) ::
          :ok | {:error, Grammar.failure()}
  defexport validate_draft(bundles_root, bundle_name, root_tag, grammar_path, body) do
    Grammar.validate(bundles_root, bundle_name, root_tag, grammar_path, body)
  end
end
