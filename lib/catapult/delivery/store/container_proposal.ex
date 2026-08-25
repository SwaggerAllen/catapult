defmodule Catapult.Delivery.Store.ContainerProposal do
  @moduledoc """
  One proposed entry for the *next* container's `prep`
  (`delivery_container_proposals`, `systems/delivery.md`'s ORC-104
  design pass; v5 §7.8). Composite primary key `(project_id, id)`
  (ORC-87).

  **Composition proposes and never commits.** A row here is a
  computation, not a work item: nothing in this table opens a flow,
  assigns anything to a queue, or appears in a queue's population.
  Committing a proposal into an actual `prep` entry is an ordinary
  ticket-open action and stays the author's — the ticket record names
  that as out of scope explicitly, and the milestone screen that will
  render these is dashboard v3's.

  `source_container_id` is the container the proposal was computed at
  the close of; `target_queue` is the entry it is proposed *into*.
  Keeping both means a superseded proposal is answerable ("computed at
  the last close, never committed") instead of being silently
  recomputed into a duplicate.
  """

  use Ecto.Schema

  @primary_key false

  schema "delivery_container_proposals" do
    field :id, :string, primary_key: true
    field :project_id, :string, primary_key: true
    field :source_container_id, :string
    field :target_container_id, :string
    field :target_queue, :string
    field :work_item_id, :string
    field :work_item_ref, :string
    field :flow_name, :string
    field :rationale, :string
    field :computed_sequence, :integer

    timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
  end

  @type t :: %__MODULE__{}
end
