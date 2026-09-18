defmodule Catapult.Dsl.SystemStatus do
  @moduledoc """
  The platform-fixed vocabulary both bundle axes reference and neither
  declares (`workflow.md` #10, v5 §7.18-§7.19): sixteen system-status
  kinds and the five fixed agent steps. Referenced by a workflow's
  `types.<name>` `statuses:` array, which positions everything by array
  index rather than by a named predecessor.

  Not declarable by either axis — that is what lets a blocked ticket
  re-resolve against these anchors across a workflow cutover (v5
  §7.19) — so this module is a closed constant table, never a registry.

  **`design`, `architecture` and `implementation` stop being kinds**
  (`systems/core_dsl.md`'s #45.4): they return as `name:` values on
  `generation` entries, so `generation` is the one generation-shaped
  kind. **`pending` leaves the table altogether** (`workflow.md` #25):
  it is an engine-set flag every agent-balled position carries until an
  agent picks the work up, never a declared entry, so there is nothing
  here — and nothing in `Catapult.Dsl.Workflow` — checking a `pending`
  predecessor any more.
  """

  @typedoc "One of the fixed system-status kinds."
  @type kind ::
          :backlog
          | :generation
          | :critique
          | :checks
          | :reconcile
          | :merge
          | :deploy
          | :validating
          | :blocked
          | :stubbed
          | :setup
          | :prep
          | :main
          | :retro
          | :cleanup
          | :terminal

  @typedoc "Who holds the ball while a ticket sits at a status of this kind."
  @type ball :: :author | :plane | :agent | :world | :varies

  @typedoc "One of the five fixed agent steps a chain's tier may run as."
  @type agent_step :: :design | :dev | :critique | :reconcile | :validate

  @statuses [
    {:backlog, :author},
    {:generation, :agent},
    {:critique, :agent},
    {:checks, :world},
    {:reconcile, :agent},
    {:merge, :plane},
    {:deploy, :world},
    {:validating, :plane},
    {:blocked, :varies},
    {:stubbed, :world},
    {:setup, :agent},
    {:prep, :varies},
    {:main, :varies},
    {:retro, :agent},
    {:cleanup, :varies},
    {:terminal, nil}
  ]

  @agent_steps [:design, :dev, :critique, :reconcile, :validate]

  @doc "The fixed system-status kinds, in the order workflow.md #10 declares them."
  @spec kinds() :: [kind()]
  def kinds, do: Enum.map(@statuses, &elem(&1, 0))

  @doc "Whether `name` is one of the fixed system-status kinds."
  @spec kind?(term()) :: boolean()
  def kind?(name), do: name in kinds()

  @doc "The `ball` a status of `kind` carries, or `nil` for `:terminal` (no ball to hold)."
  @spec ball(kind()) :: ball() | nil
  def ball(kind), do: Keyword.fetch!(@statuses, kind)

  @agent_balled_names for {kind, :agent} <- @statuses, do: Atom.to_string(kind)

  @doc """
  Whether the status *name* `name` is agent-balled — `workflow.md`
  #10's `ball` column reading `agent`, as a string, since a `statuses:`
  array entry carries a bundle-authored string rather than one of this
  module's atoms.
  """
  @spec agent_balled?(String.t()) :: boolean()
  def agent_balled?(name) when is_binary(name), do: name in @agent_balled_names

  @generation_shaped_names ~w(generation)

  @doc """
  Whether the status *name* `name` is generation-shaped — `generation`
  alone (`workflow.md` #10): named once here rather than at every call
  site that needs "an agent writes here."
  """
  @spec generation_shaped?(String.t()) :: boolean()
  def generation_shaped?(name) when is_binary(name), do: name in @generation_shaped_names

  @review_shaped_names ~w(critique reconcile)

  @doc """
  Whether the status *name* `name` is review-shaped — `critique` or
  `reconcile` (`workflow.md` #10): an agent run judging an artifact
  that already exists, rather than originating one.
  """
  @spec review_shaped?(String.t()) :: boolean()
  def review_shaped?(name) when is_binary(name), do: name in @review_shaped_names

  @doc "The five fixed agent steps a chain's tier may run as."
  @spec agent_steps() :: [agent_step()]
  def agent_steps, do: @agent_steps

  @doc "Whether `name` is one of the five fixed agent steps."
  @spec agent_step?(term()) :: boolean()
  def agent_step?(name), do: name in @agent_steps

  @doc """
  Every non-terminal status can be kicked to `:blocked` (v5 §7.19: "the
  automation kicks tickets into it" — a plane rule, not declared data).
  """
  @spec can_block?(kind()) :: boolean()
  def can_block?(:terminal), do: false
  def can_block?(:blocked), do: false
  def can_block?(kind) when is_atom(kind), do: kind?(kind)

  @doc "Whether `name` — an atom or the bundle string a projection column stores — names the fixed `:blocked` kind."
  @spec blocked?(term()) :: boolean()
  def blocked?(:blocked), do: true
  def blocked?("blocked"), do: true
  def blocked?(_name), do: false
end
