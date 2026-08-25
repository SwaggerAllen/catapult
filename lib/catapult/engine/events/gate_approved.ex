defmodule Catapult.Engine.Events.GateApproved do
  @moduledoc """
  A declared workflow gate was signed off (v5 §7.16,
  `systems/engine.md`'s ORC-34 design pass). Version 1.

  Records only enough for a ticket's projected status to move forward
  and for the aggregate's own comment-count check to reset — no
  `body_sha` or other content-identity field, since what a *passed*
  gate pins stays exactly as open as §7.16 already left it.
  """

  @enforce_keys [:project_id, :flow_id, :gate]
  @derive Jason.Encoder
  defstruct [:project_id, :flow_id, :gate, :actor_id]

  @type t :: %__MODULE__{
          project_id: binary(),
          flow_id: binary(),
          gate: String.t(),
          actor_id: binary() | nil
        }
end
