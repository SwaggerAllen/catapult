defmodule Catapult.Dsl.SystemStatus do
  @moduledoc """
  The platform-fixed vocabulary both bundle axes reference and neither
  declares (dsl-syntax.md §15.1, v5 §7.18-§7.19): the eleven system
  statuses and the five agent steps. Referenced by a chain's `delivery:`
  block (`phase:` against `kinds/0`, `agent_step:` against
  `agent_steps/0`) and by a workflow's `gates/<gate>.yaml` /
  `environments/<env>.yaml` `after:` predecessor (§15.2, §15.4).

  Not declarable by either axis (dsl-syntax.md §15.1) — that is what
  lets a blocked ticket re-resolve against these anchors across a
  workflow cutover (v5 §7.19) — so this module is a closed constant
  table, never a registry.
  """

  @typedoc "One of the eleven fixed system-status kinds."
  @type kind ::
          :backlog
          | :queue
          | :generation
          | :fanout
          | :checks
          | :merge
          | :deploy
          | :validating
          | :blocked
          | :stubbed
          | :terminal

  @typedoc "Who holds the ball while a ticket sits at a status of this kind."
  @type ball :: :author | :plane | :agent | :world | :varies

  @typedoc "One of the five fixed agent steps a chain's `delivery.agent_step` may name."
  @type agent_step :: :design | :dev | :reconcile | :validate | :boundary

  @statuses [
    {:backlog, :author},
    {:queue, :plane},
    {:generation, :agent},
    {:fanout, :plane},
    {:checks, :world},
    {:merge, :agent},
    {:deploy, :world},
    {:validating, :plane},
    {:blocked, :varies},
    {:stubbed, :world},
    {:terminal, nil}
  ]

  @agent_steps [:design, :dev, :reconcile, :validate, :boundary]

  @doc "The eleven system-status kinds, in the order dsl-syntax.md §15.1 declares them."
  @spec kinds() :: [kind()]
  def kinds, do: Enum.map(@statuses, &elem(&1, 0))

  @doc "Whether `name` is one of the eleven fixed system-status kinds."
  @spec kind?(term()) :: boolean()
  def kind?(name), do: name in kinds()

  @doc "The `ball` a status of `kind` carries, or `nil` for `:terminal` (no ball to hold)."
  @spec ball(kind()) :: ball() | nil
  def ball(kind), do: Keyword.fetch!(@statuses, kind)

  @doc "The five fixed agent steps a chain's `delivery.agent_step` may name."
  @spec agent_steps() :: [agent_step()]
  def agent_steps, do: @agent_steps

  @doc "Whether `name` is one of the five fixed agent steps."
  @spec agent_step?(term()) :: boolean()
  def agent_step?(name), do: name in @agent_steps

  @doc """
  A `queue` precedes every `generation` and every `deploy` (dsl-syntax.md
  §15.1, §13) — a structural fact about the fixed skeleton, not something
  any bundle declares, so it is a constant rather than a check over
  bundle content.
  """
  @spec queue_precedes?(kind()) :: boolean()
  def queue_precedes?(kind), do: kind in [:generation, :deploy]

  @doc """
  Every non-terminal status can be kicked to `:blocked` (v5 §7.19: "the
  automation kicks tickets into it" — a plane rule, not declared data).
  This is what makes "every generation status has at least one blocked
  exit" (dsl-syntax.md §13) a fact about the fixed skeleton rather than
  about any one workflow bundle; see `Catapult.Dsl.Workflow.Graph` for
  where that invariant is exercised at load time.
  """
  @spec can_block?(kind()) :: boolean()
  def can_block?(:terminal), do: false
  def can_block?(:blocked), do: false
  def can_block?(kind) when is_atom(kind), do: kind?(kind)
end
