defmodule Catapult.Engine.Store do
  @moduledoc """
  The engine's persistence subcomponent (conventions §4/§6): owns the
  universal projection tables and their queries. Function-shaped
  exports, never generic CRUD — the reducer's own vocabulary (mint a
  node, write an edge, commit a draft) rather than a DAO.

  Every write here is idempotent by construction where the event log
  can replay it: `upsert_node/1` and `insert_edge/1` use natural keys
  (`{project_id, tier, scope_key}`, `{edge_name, source, target}`) so
  applying the same event twice — replay, or a re-delivered projector
  message — lands the same row rather than a duplicate or a conflict.
  """

  import Ecto.Query

  alias Catapult.Engine.Store.ActiveBundleVersion
  alias Catapult.Engine.Store.Draft
  alias Catapult.Engine.Store.Edge
  alias Catapult.Engine.Store.Flow
  alias Catapult.Engine.Store.Fragment
  alias Catapult.Engine.Store.Node
  alias Catapult.Engine.Store.Review
  alias Catapult.Repo

  ## Nodes

  @doc """
  Inserts a node if `id` is unused, or updates the existing row.

  Every field the caller supplies is written; fields it omits keep
  their current value on update (a `DraftCommitted` updates `status`/
  `fields`/`body_sha`/`committed_sequence`/`current_draft_id` without
  touching `parent_node_id`, which a mint set once and a later commit
  never revisits).
  """
  @spec upsert_node(map()) :: Node.t()
  def upsert_node(attrs) do
    id = Map.fetch!(attrs, :id)
    replace = Map.keys(Map.delete(attrs, :id))

    %Node{id: id}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(
      on_conflict: {:replace, replace},
      conflict_target: :id
    )
  end

  @doc "Mints a node if `{project_id, tier, scope_key}` doesn't already exist. Idempotent on replay."
  @spec mint_node(map()) :: Node.t()
  def mint_node(attrs) do
    %Node{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(
      on_conflict: :nothing,
      conflict_target: [:project_id, :tier, :scope_key]
    )
    |> case do
      %Node{id: nil} -> get_node_by_scope!(attrs.project_id, attrs.tier, attrs.scope_key)
      node -> node
    end
  end

  @spec get_node(binary()) :: Node.t() | nil
  def get_node(id), do: Repo.get(Node, id)

  @doc "Marks an existing node approved (`DraftApproved`) — an update, not an upsert: the row already exists."
  @spec approve_node(binary()) :: :ok
  def approve_node(id) do
    Repo.update_all(from(n in Node, where: n.id == ^id), set: [status: :approved])
    :ok
  end

  @spec get_node_by_scope!(binary(), String.t(), map()) :: Node.t()
  def get_node_by_scope!(project_id, tier, scope_key) do
    Repo.get_by!(Node, project_id: project_id, tier: tier, scope_key: scope_key)
  end

  @spec get_node_by_scope(binary(), String.t(), map()) :: Node.t() | nil
  def get_node_by_scope(project_id, tier, scope_key) do
    Repo.get_by(Node, project_id: project_id, tier: tier, scope_key: scope_key)
  end

  @spec list_nodes(binary(), String.t()) :: [Node.t()]
  def list_nodes(project_id, tier) do
    Repo.all(from n in Node, where: n.project_id == ^project_id and n.tier == ^tier)
  end

  @spec list_children(binary()) :: [Node.t()]
  def list_children(parent_node_id) do
    Repo.all(from n in Node, where: n.parent_node_id == ^parent_node_id)
  end

  ## Edges

  @spec insert_edge(map()) :: Edge.t()
  def insert_edge(attrs) do
    %Edge{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(
      on_conflict: :nothing,
      conflict_target: [:edge_name, :source_node_id, :target_node_id]
    )
  end

  @doc "Every edge instance walking forward from `node_id` along `edge_name` (dsl-syntax.md §7)."
  @spec edges_from(binary(), String.t()) :: [Edge.t()]
  def edges_from(node_id, edge_name) do
    Repo.all(from e in Edge, where: e.source_node_id == ^node_id and e.edge_name == ^edge_name)
  end

  @doc "Every edge instance walking reversed from `node_id` along `edge_name` (§7.1's `~` suffix)."
  @spec edges_to(binary(), String.t()) :: [Edge.t()]
  def edges_to(node_id, edge_name) do
    Repo.all(from e in Edge, where: e.target_node_id == ^node_id and e.edge_name == ^edge_name)
  end

  ## Fragments

  @spec insert_fragment(map()) :: Fragment.t()
  def insert_fragment(attrs) do
    %Fragment{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :id)
  end

  @spec fragments(binary(), String.t()) :: [Fragment.t()]
  def fragments(owner_node_id, kind) do
    Repo.all(from f in Fragment, where: f.owner_node_id == ^owner_node_id and f.kind == ^kind)
  end

  ## Drafts

  @spec insert_draft(map()) :: Draft.t()
  def insert_draft(attrs) do
    %Draft{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :id)
  end

  @spec get_draft(binary()) :: Draft.t() | nil
  def get_draft(id), do: Repo.get(Draft, id)

  @spec set_draft_status(binary(), :approved | :discarded) :: :ok
  def set_draft_status(id, status) do
    Repo.update_all(from(d in Draft, where: d.id == ^id), set: [status: status])
    :ok
  end

  ## Reviews

  @spec insert_review(map()) :: Review.t()
  def insert_review(attrs) do
    %Review{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :id)
  end

  @spec reviews_for_draft(binary()) :: [Review.t()]
  def reviews_for_draft(draft_id) do
    Repo.all(from r in Review, where: r.draft_id == ^draft_id, order_by: r.inserted_at)
  end

  ## Flows

  @spec insert_flow(map()) :: Flow.t()
  def insert_flow(attrs) do
    %Flow{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :id)
  end

  @spec complete_flow(binary(), integer()) :: :ok
  def complete_flow(id, sequence) do
    Repo.update_all(from(f in Flow, where: f.id == ^id),
      set: [status: :completed, completed_sequence: sequence]
    )

    :ok
  end

  @spec get_flow(binary()) :: Flow.t() | nil
  def get_flow(id), do: Repo.get(Flow, id)

  ## Active bundle versions — the ninth projection

  @spec flip_active_bundle_version(map()) :: ActiveBundleVersion.t()
  def flip_active_bundle_version(attrs) do
    %ActiveBundleVersion{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :id)
  end

  @doc """
  The bundle version active on `axis` as of `at_sequence` (default:
  the latest known) — a log-order lookup, never a read of `core_dsl`'s
  currently-loaded bundle (`systems/engine.md`).
  """
  @spec current_bundle_version(binary(), :chain | :workflow, integer() | :latest) ::
          ActiveBundleVersion.t() | nil
  def current_bundle_version(project_id, axis, at_sequence \\ :latest) do
    base =
      from v in ActiveBundleVersion,
        where: v.project_id == ^project_id and v.axis == ^axis,
        order_by: [desc: v.became_current_sequence],
        limit: 1

    query =
      case at_sequence do
        :latest -> base
        sequence -> from v in base, where: v.became_current_sequence <= ^sequence
      end

    Repo.one(query)
  end
end
