defmodule Catapult.Engine.Events.DraftApproved do
  @moduledoc """
  A pending draft was approved. Version 1. Approval is a
  status, and the transition is the record (v5 §7.16) — no separate
  approval object; who approved is `actor_id` on this event.
  """

  @enforce_keys [:project_id, :node_id, :draft_id]
  @derive Jason.Encoder
  defstruct [:project_id, :node_id, :draft_id, :actor_id]

  @type t :: %__MODULE__{
          project_id: binary(),
          node_id: binary(),
          draft_id: binary(),
          actor_id: binary() | nil
        }
end
