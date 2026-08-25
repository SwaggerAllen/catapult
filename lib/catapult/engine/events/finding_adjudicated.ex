defmodule Catapult.Engine.Events.FindingAdjudicated do
  @moduledoc """
  One finding a container carried left adjudicated (v5 §7.8,
  `systems/delivery.md`'s ORC-104 design pass). Version 1.

  **Every carried finding leaves adjudicated: filed under its own key,
  or declined with a recorded reason. Neither is deferral.** The
  measurement that put this in the ticket: a close carried twelve
  findings, filed one unrelated proposal, and left no record that any
  of the twelve had been read. This event is the record — one per
  finding, with nowhere for a thirteenth outcome to hide.

  `disposition` is `:filed` (with `filed_key` naming the work item it
  became) or `:declined` (with `reason` carrying why). The aggregate
  rejects a `:filed` with no key and a `:declined` with no reason,
  because a disposition without its evidence is exactly the silent
  deferral this event exists to make impossible.
  """

  @enforce_keys [:project_id, :container_id, :finding_id, :disposition]
  @derive Jason.Encoder
  defstruct [
    :project_id,
    :container_id,
    :finding_id,
    :disposition,
    :filed_key,
    :reason,
    :actor_id
  ]

  @typedoc "How the finding left: filed under its own key, or declined with a reason."
  @type disposition :: :filed | :declined

  @type t :: %__MODULE__{
          project_id: binary(),
          container_id: binary(),
          finding_id: binary(),
          disposition: disposition(),
          filed_key: String.t() | nil,
          reason: String.t() | nil,
          actor_id: binary() | nil
        }
end
