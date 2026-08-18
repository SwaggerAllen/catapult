defmodule Catapult.Dsl.Dialect do
  @moduledoc """
  A dialect is core plus an extension set plus defaults (dsl-syntax.md
  §12): `design` (full Catapult, both axes) and `runtime` (the embedded
  generation runtime, v5 §10 — no review lifecycle, no git bodies, and
  therefore no workflow bundle at all — v5 §7.18: "a workflow bundle
  there is not merely unused but incoherent, and the loader should say
  so rather than accept it").

  Neither dialect registers any extension yet
  (`systems/core_dsl.md`'s Initial vs Target): delivery's annotations,
  generator types and context sources arrive with the delivery system.
  The extension lists here are the seam that ships them, not a promise
  that they are populated today.
  """

  @enforce_keys [:name, :extensions, :loads_workflow?]
  defstruct [:name, :extensions, :loads_workflow?]

  @type t :: %__MODULE__{name: String.t(), extensions: [module()], loads_workflow?: boolean()}

  @names ~w(design runtime)

  @doc "The `design` dialect: full Catapult, both bundle axes."
  @spec design() :: t()
  def design, do: %__MODULE__{name: "design", extensions: [], loads_workflow?: true}

  @doc "The `runtime` dialect: the embedded generation runtime, chain axis only."
  @spec runtime() :: t()
  def runtime, do: %__MODULE__{name: "runtime", extensions: [], loads_workflow?: false}

  @doc "Resolves a dialect by name, or `:error` for anything outside the registered two."
  @spec by_name(String.t()) :: {:ok, t()} | :error
  def by_name("design"), do: {:ok, design()}
  def by_name("runtime"), do: {:ok, runtime()}
  def by_name(_other), do: :error

  @doc "The registered dialect names."
  @spec names() :: [String.t()]
  def names, do: @names
end
