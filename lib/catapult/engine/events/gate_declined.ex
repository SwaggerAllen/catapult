defmodule Catapult.Engine.Events.GateDeclined do
  @moduledoc """
  A declared workflow gate was thrown back (v5 §7.16,
  `systems/engine.md`'s ORC-34 design pass, corrected on design
  review). Version 1.

  `throwback_to` is the resolved target the gate's own `throwback:`
  list named — load-time-guaranteed reachable
  (`Catapult.Dsl.Workflow.gate_throwback_problems/2`) — and moves the
  ticket's projected status straight there, no lookup needed.
  `since_sequence` is the log position `Catapult.Engine.Projections
  .GateComments.last_resolution_sequence/2` read at the
  command-construction boundary, copied onto this event rather than
  recomputed inside the aggregate (this system's purity floor);
  `Catapult.Engine.Projections.CommentFeedback` reads it back to know
  where to start folding. It is a log position, not a content claim,
  and does not pin what this gate approved — §7.16's own still-open
  question.
  """

  @enforce_keys [:project_id, :flow_id, :gate, :throwback_to, :since_sequence]
  @derive Jason.Encoder
  defstruct [:project_id, :flow_id, :gate, :throwback_to, :since_sequence, :actor_id]

  @type t :: %__MODULE__{
          project_id: binary(),
          flow_id: binary(),
          gate: String.t(),
          throwback_to: String.t(),
          since_sequence: non_neg_integer() | nil,
          actor_id: binary() | nil
        }
end
