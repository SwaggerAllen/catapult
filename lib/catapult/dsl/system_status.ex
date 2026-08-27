defmodule Catapult.Dsl.SystemStatus do
  @moduledoc """
  The platform-fixed vocabulary both bundle axes reference and neither
  declares (dsl-syntax.md §15.1, v5 §7.18-§7.19): the system-status
  kinds and the five fixed agent steps. Referenced by a chain's
  `delivery:` block (`phase:` against `kinds/0`, `agent_step:` against
  `agent_steps/0`) and by a workflow's `types/<name>.yaml` `statuses:`
  array (§15.1-§15.2), which positions everything by array index
  rather than by a named predecessor (§15.3).

  Not declarable by either axis (dsl-syntax.md §15.1) — that is what
  lets a blocked ticket re-resolve against these anchors across a
  workflow cutover (v5 §7.19) — so this module is a closed constant
  table, never a registry.

  **Renamed from `queue` to `pending`, at ORC-104's dev pass** (§15.1):
  a single work item's own wait-for-dispatch status and a container's
  own named queue position used to share one word; once both could
  appear in the same declared array, the collision stopped being
  theoretical. `pending` keeps the fixed-vocabulary meaning exactly —
  "committed, awaiting dispatch capacity" — freeing "queue" for the
  sense the rest of dsl-syntax.md §15 needs it in.

  **`:boundary` retired from `agent_step/0`, at the same pass** (§15.1,
  `systems/core_dsl.md`): it used to name "the milestone pass" as a
  single static agent step, but no tier's `delivery:` ever actually
  named it — a container's progress is a declared sequence of queues
  (§15.2-§15.8), not one fixed pass. The work it stood in for —
  `retro`'s backward-looking pass and a nested container's own
  forward-looking `setup` — dispatches as an ordinary flow instance
  through a queue's declared `flow:`, needing no reserved slot here.
  """

  @typedoc "One of the fixed system-status kinds."
  @type kind ::
          :backlog
          | :pending
          | :generation
          | :critique
          | :fanout
          | :checks
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

  @typedoc "One of the five fixed agent steps a chain's `delivery.agent_step` may name."
  @type agent_step :: :design | :dev | :critique | :reconcile | :validate

  @statuses [
    {:backlog, :author},
    {:pending, :plane},
    {:generation, :agent},
    {:critique, :agent},
    {:fanout, :plane},
    {:checks, :world},
    {:merge, :agent},
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

  @doc "The fixed system-status kinds, in the order dsl-syntax.md §15.1 declares them."
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
  Whether the status *name* `name` is agent-balled — §15.1's `ball`
  column reading `agent`, as a string, since a `statuses:` array entry
  carries a bundle-authored string rather than one of this module's
  atoms (`Catapult.Dsl.Fields`'s no-`to_atom`-on-bundle-content
  discipline).

  This is the raw ball column and nothing more. dsl-syntax.md §15.10's
  sub-array anchor rule wants the *non-critique* agent-balled entries;
  that exclusion is drawn at its own call site, where §15.5's reason
  for drawing it is written down, rather than folded in here where a
  reader would have to guess which of the two questions this answers.
  """
  @spec agent_balled?(String.t()) :: boolean()
  def agent_balled?(name) when is_binary(name), do: name in @agent_balled_names

  @doc "The five fixed agent steps a chain's `delivery.agent_step` may name."
  @spec agent_steps() :: [agent_step()]
  def agent_steps, do: @agent_steps

  @doc "Whether `name` is one of the five fixed agent steps."
  @spec agent_step?(term()) :: boolean()
  def agent_step?(name), do: name in @agent_steps

  @doc """
  A `pending` precedes every `generation` and every `deploy`
  (dsl-syntax.md §15.1, §13) — a structural fact about the fixed
  skeleton, not something any bundle declares, so it is a constant
  rather than a check over bundle content.
  """
  @spec pending_precedes?(kind()) :: boolean()
  def pending_precedes?(kind), do: kind in [:generation, :deploy]

  @doc """
  Every non-terminal status can be kicked to `:blocked` (v5 §7.19: "the
  automation kicks tickets into it" — a plane rule, not declared data).
  This is what makes "every generation status has at least one blocked
  exit" (dsl-syntax.md §13) a fact about the fixed skeleton rather than
  about any one workflow bundle; see `Catapult.Dsl.Workflow` for where
  that invariant is exercised at load time.
  """
  @spec can_block?(kind()) :: boolean()
  def can_block?(:terminal), do: false
  def can_block?(:blocked), do: false
  def can_block?(kind) when is_atom(kind), do: kind?(kind)
end
