defmodule Catapult.Engine.Events.ContainerQueueAdvanced do
  @moduledoc """
  An active container's current queue moved (dsl-syntax.md §15.7-§15.8).
  Version 1.

  Forward and backward are the same event with a different `reason`,
  because they are the same fact — which queue is current now — and
  §15.6 refuses a separate stored `blocked` position for exactly this
  reason ("fully described by 'at Q, blocked by blocks:'s target'").
  The three reasons are the three the grammar admits, and there is no
  fourth:

  * `:resolved` — forward: this queue's population emptied of
    unresolved work and nothing that `blocks:` it still holds work.
  * `:repopulated` — backward: a resolved queue un-resolved because
    its population refilled. A queue is a query (§15.7), so this needs
    no gate and no separate "went backward" concept.
  * `:throwback` — backward: a gate the container's own array cites
    rejected to an earlier entry in that same array (§15.4's
    `throwback:`, §15.8's second way).

  `actor_id` is how "who approved" is answerable from the log: approval
  is the transition itself (v5 §7.16), there is no approval object, and
  a container's two human transitions — the author's manual pass and
  the author's read of `retro`'s proposals — are ordinary gate
  advances recorded with their actor.
  """

  @enforce_keys [:project_id, :container_id, :from_queue, :to_queue, :reason]
  @derive Jason.Encoder
  defstruct [:project_id, :container_id, :from_queue, :to_queue, :reason, :actor_id]

  @typedoc "Why the current queue moved — see the moduledoc."
  @type reason :: :resolved | :repopulated | :throwback

  @type t :: %__MODULE__{
          project_id: binary(),
          container_id: binary(),
          from_queue: String.t(),
          to_queue: String.t(),
          reason: reason(),
          actor_id: binary() | nil
        }
end
