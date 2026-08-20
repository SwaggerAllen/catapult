defmodule Catapult.Engine.Commands.ApproveDraft do
  @moduledoc "Approves a node's pending draft (v5 §7.16 — approval is a status; the transition is the record)."

  @enforce_keys [:project_id, :node_id, :draft_id]
  defstruct [:project_id, :node_id, :draft_id, :actor_id]
end
