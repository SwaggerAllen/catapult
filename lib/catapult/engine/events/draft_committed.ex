defmodule Catapult.Engine.Events.DraftCommitted do
  @moduledoc """
  A draft body was committed for a node (v4 §A.3.1/§A.3.2 carried
  forward, dsl-syntax.md §3). Version 1.

  The payload is fully self-describing: `mints`, `edges` and
  `produces` are already-extracted structured facts (fanout children,
  declared dependency/reference/policy_application instances, authored
  fragments) rather than a raw committed body — extraction against the
  bundle's `declared_in` paths happens at the command edge (a later
  ticket's commit path, `systems/core_dsl.md`'s grammar machinery),
  never inside the reducer, so replay never needs to re-read git
  content. This is the "inject at the command edge" half of the purity
  floor applied to body parsing, not only to clocks/ids.
  """

  @enforce_keys [:project_id, :node_id, :tier, :scope_key, :draft_id, :body_sha, :committed_at]
  @derive Jason.Encoder
  defstruct [
    :project_id,
    :node_id,
    :tier,
    :scope_key,
    :parent_node_id,
    :draft_id,
    :body_sha,
    :committed_at,
    :actor_id,
    fields: %{},
    mints: [],
    edges: [],
    produces: []
  ]

  @type mint :: %{
          node_id: binary(),
          tier: String.t(),
          scope_key: map(),
          edge_name: String.t(),
          edge_type: :fanout
        }

  @type declared_edge :: %{
          edge_name: String.t(),
          type: :reference | :dependency | :policy_application,
          target_node_id: binary()
        }

  @typedoc """
  `id` is deliberately absent: the reducer derives a fragment's id
  deterministically from `{owner_node_id, kind, author_node_id}` (a
  natural key, same move as an edge's id) rather than requiring the
  command edge to mint one for a fact that already has a unique key.
  """
  @type produced_fragment :: %{
          owner_node_id: binary(),
          kind: String.t(),
          content: String.t()
        }

  @type t :: %__MODULE__{
          project_id: binary(),
          node_id: binary(),
          tier: String.t(),
          scope_key: map(),
          parent_node_id: binary() | nil,
          draft_id: binary(),
          body_sha: String.t(),
          committed_at: DateTime.t(),
          actor_id: binary() | nil,
          fields: map(),
          mints: [mint()],
          edges: [declared_edge()],
          produces: [produced_fragment()]
        }
end
