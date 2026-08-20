defmodule Catapult.Engine.Events.DraftDiscarded do
  @moduledoc """
  A corrective event (v4 §A.3.1): the pending draft is discarded
  without approval. Version 1. State corrections happen by appending
  corrective events, never by editing or deleting the original.
  """

  @enforce_keys [:project_id, :node_id, :draft_id]
  @derive Jason.Encoder
  defstruct [:project_id, :node_id, :draft_id, :actor_id, :reason]

  @type t :: %__MODULE__{
          project_id: binary(),
          node_id: binary(),
          draft_id: binary(),
          actor_id: binary() | nil,
          reason: String.t() | nil
        }
end
