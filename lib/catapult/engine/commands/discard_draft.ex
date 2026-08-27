defmodule Catapult.Engine.Commands.DiscardDraft do
  @moduledoc "Discards a node's pending draft without approval (a corrective act)."

  @enforce_keys [:project_id, :node_id, :draft_id]
  defstruct [:project_id, :node_id, :draft_id, :actor_id, :reason]
end
