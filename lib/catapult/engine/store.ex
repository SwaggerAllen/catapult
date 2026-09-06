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
  alias Catapult.Engine.Store.Container
  alias Catapult.Engine.Store.ContainerFinding
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
    project_id = Map.fetch!(attrs, :project_id)
    replace = Map.keys(Map.delete(attrs, :id))

    retry_on_deadlock(fn ->
      %Node{id: id, project_id: project_id}
      |> Ecto.Changeset.change(attrs)
      |> Repo.insert!(
        on_conflict: {:replace, replace},
        conflict_target: [:project_id, :id]
      )
    end)
  end

  @doc "Mints a node if `{project_id, tier, scope_key}` doesn't already exist. Idempotent on replay."
  @spec mint_node(map()) :: Node.t()
  def mint_node(attrs) do
    retry_on_deadlock(fn ->
      %Node{}
      |> Ecto.Changeset.change(attrs)
      |> Repo.insert!(
        on_conflict: :nothing,
        conflict_target: [:project_id, :tier, :scope_key]
      )
    end)
    |> case do
      %Node{id: nil} -> get_node_by_scope!(attrs.project_id, attrs.tier, attrs.scope_key)
      node -> node
    end
  end

  # `engine_nodes` carries a second unique index beyond whichever one a
  # caller names as its `conflict_target` (`project_id, id` here,
  # `project_id, tier, scope_key` in `mint_node/1`) — Postgres checks
  # every unique index on every insert regardless of which one
  # `ON CONFLICT` names, and two concurrent upserts landing on that
  # other index's same btree page can deadlock each other even though
  # neither targets it. One retry is the standard remedy (the losing
  # side is a clean abort, not a corrupted write) rather than a schema
  # change to a load-bearing natural key.
  @deadlock_codes [:deadlock_detected, :serialization_failure]

  defp retry_on_deadlock(fun) do
    fun.()
  rescue
    e in Postgrex.Error ->
      if match?(%{postgres: %{code: code}} when code in @deadlock_codes, e) do
        fun.()
      else
        reraise e, __STACKTRACE__
      end
  end

  @doc "A node is addressed by `(project_id, id)` — a bare id is not unique across projects (ORC-87)."
  @spec get_node(binary(), binary()) :: Node.t() | nil
  def get_node(project_id, id), do: Repo.get_by(Node, project_id: project_id, id: id)

  @doc "Marks an existing node approved (`DraftApproved`) — an update, not an upsert: the row already exists."
  @spec approve_node(binary(), binary()) :: :ok
  def approve_node(project_id, id) do
    Repo.update_all(
      from(n in Node, where: n.project_id == ^project_id and n.id == ^id),
      set: [status: :approved]
    )

    :ok
  end

  @doc """
  Resets a node whose pending draft was discarded (`DraftDiscarded`,
  ORC-229) back to `:absent` with `current_draft_id`/`body_sha`
  cleared — the identical row shape a never-drafted node already
  carries, which is what makes `ReadyScopes.ready/3`'s own
  `node.status == :absent` filter admit it again with no filter change
  of its own.
  """
  @spec discard_node(binary(), binary()) :: :ok
  def discard_node(project_id, id) do
    Repo.update_all(
      from(n in Node, where: n.project_id == ^project_id and n.id == ^id),
      set: [status: :absent, current_draft_id: nil, body_sha: nil]
    )

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
      conflict_target: [:project_id, :edge_name, :source_node_id, :target_node_id]
    )
  end

  @doc "Every edge instance walking forward from `node_id` along `edge_name` (dsl-syntax.md §7)."
  @spec edges_from(binary(), binary(), String.t()) :: [Edge.t()]
  def edges_from(project_id, node_id, edge_name) do
    Repo.all(
      from e in Edge,
        where:
          e.project_id == ^project_id and e.source_node_id == ^node_id and
            e.edge_name == ^edge_name
    )
  end

  @doc "Every edge instance walking reversed from `node_id` along `edge_name` (§7.1's `~` suffix)."
  @spec edges_to(binary(), binary(), String.t()) :: [Edge.t()]
  def edges_to(project_id, node_id, edge_name) do
    Repo.all(
      from e in Edge,
        where:
          e.project_id == ^project_id and e.target_node_id == ^node_id and
            e.edge_name == ^edge_name
    )
  end

  @doc """
  Every edge instance leaving `node_id`, any name — the predicate
  language's unrestricted `reaches/2` walk (dsl-syntax.md §8), which
  names no edge the way `has_edge`/`count`/a context-walk hop do.
  """
  @spec edges_from(binary(), binary()) :: [Edge.t()]
  def edges_from(project_id, node_id) do
    Repo.all(from e in Edge, where: e.project_id == ^project_id and e.source_node_id == ^node_id)
  end

  ## Fragments

  @spec insert_fragment(map()) :: Fragment.t()
  def insert_fragment(attrs) do
    %Fragment{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(on_conflict: :nothing, conflict_target: [:project_id, :id])
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
    |> Repo.insert!(on_conflict: :nothing, conflict_target: [:project_id, :id])
  end

  @spec get_draft(binary(), binary()) :: Draft.t() | nil
  def get_draft(project_id, id), do: Repo.get_by(Draft, project_id: project_id, id: id)

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
    |> Repo.insert!(on_conflict: :nothing, conflict_target: [:project_id, :id])
  end

  @spec reviews_for_draft(binary()) :: [Review.t()]
  def reviews_for_draft(draft_id) do
    Repo.all(from r in Review, where: r.draft_id == ^draft_id, order_by: r.inserted_at)
  end

  @doc """
  `node_id`'s own most recent review, regardless of which draft it
  landed against (`prior_review`, ORC-34, `systems/engine.md`) —
  answers a different question than `reviews_for_draft/1`, which is
  blank for a freshly regenerated draft's own review tier every time,
  exactly when "what I said last time" is the point. Project-scoped
  from the join predicate itself (`d.project_id == r.project_id`), not
  only in this function's own arguments — the precise spot the ORC-87
  bare-id gap `reviews_for_draft/1` still carries would reappear if it
  weren't.
  """
  @spec reviews_for_node(binary(), binary()) :: Review.t() | nil
  def reviews_for_node(project_id, node_id) do
    Repo.one(
      from r in Review,
        join: d in Draft,
        on: d.project_id == r.project_id and d.id == r.draft_id,
        where: d.project_id == ^project_id and d.node_id == ^node_id,
        order_by: [desc: r.inserted_at],
        limit: 1
    )
  end

  ## Flows

  @spec insert_flow(map()) :: Flow.t()
  def insert_flow(attrs) do
    %Flow{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(on_conflict: :nothing, conflict_target: [:project_id, :id])
  end

  @spec complete_flow(binary(), integer()) :: :ok
  def complete_flow(id, sequence) do
    Repo.update_all(from(f in Flow, where: f.id == ^id),
      set: [status: :completed, completed_sequence: sequence]
    )

    :ok
  end

  @spec get_flow(binary(), binary()) :: Flow.t() | nil
  def get_flow(project_id, id), do: Repo.get_by(Flow, project_id: project_id, id: id)

  ## Active bundle versions — the ninth projection

  @spec flip_active_bundle_version(map()) :: ActiveBundleVersion.t()
  def flip_active_bundle_version(attrs) do
    %ActiveBundleVersion{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(on_conflict: :nothing, conflict_target: [:project_id, :id])
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

  ## Project enumeration — the sweeper's own (systems/engine.md)

  @doc """
  Every project id with at least one row anywhere in the engine store —
  the sweeper's own enumeration, walked serially rather than fanned out
  (`Catapult.Engine.Sweeper`). No `projects` table exists here (no
  system owns that concept yet); this is the union of every table that
  already carries `project_id`, which is every project the engine has
  ever heard from.
  """
  @spec list_project_ids() :: [binary()]
  def list_project_ids do
    [
      from(n in Node, distinct: true, select: n.project_id),
      from(f in Flow, distinct: true, select: f.project_id),
      from(v in ActiveBundleVersion, distinct: true, select: v.project_id)
    ]
    |> Enum.flat_map(&Repo.all/1)
    |> Enum.uniq()
  end

  ## Containers (ORC-104, systems/engine.md; dsl-syntax.md §15.6-§15.8)

  @doc """
  Records a minted container instance. Idempotent on replay: a second
  `ContainerMinted` for the same `(project_id, id)` lands the same row
  rather than a duplicate, the same natural-key discipline
  `mint_node/1` already uses.
  """
  @spec mint_container(map()) :: Container.t()
  def mint_container(attrs) do
    %Container{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(on_conflict: :nothing, conflict_target: [:project_id, :id])
  end

  @doc "Marks a minted instance active at `queue` — its own first declared entry (§15.8)."
  @spec activate_container(binary(), binary(), String.t(), integer()) :: :ok
  def activate_container(project_id, id, queue, sequence) do
    update_container(project_id, id,
      state: :active,
      current_queue: queue,
      current_queue_sequence: sequence,
      activated_sequence: sequence
    )
  end

  @doc "Moves an active instance's current queue — forward or backward alike (§15.7-§15.8)."
  @spec advance_container_queue(binary(), binary(), String.t(), integer()) :: :ok
  def advance_container_queue(project_id, id, queue, sequence) do
    update_container(project_id, id, current_queue: queue, current_queue_sequence: sequence)
  end

  @doc "Marks an instance closed (§15.6)."
  @spec close_container(binary(), binary(), integer()) :: :ok
  def close_container(project_id, id, sequence) do
    update_container(project_id, id, state: :closed, closed_sequence: sequence)
  end

  @doc "Records the intent to flip a container's aggregated flag set (v5 §7.1, §7.8)."
  @spec request_flag_set_flip(binary(), binary(), [String.t()], integer()) :: :ok
  def request_flag_set_flip(project_id, id, flags, sequence) do
    update_container(project_id, id,
      flag_set: flags,
      flag_set_state: :requested,
      flag_set_sequence: sequence
    )
  end

  @doc "Records the world's confirmation that a requested flag set is on (v5 §7.1)."
  @spec record_flag_set_flip(binary(), binary(), integer()) :: :ok
  def record_flag_set_flip(project_id, id, sequence) do
    update_container(project_id, id, flag_set_state: :flipped, flag_set_sequence: sequence)
  end

  @doc "A container is addressed by `(project_id, id)` — a bare id is not unique across projects (ORC-87)."
  @spec get_container(binary(), binary()) :: Container.t() | nil
  def get_container(project_id, id), do: Repo.get_by(Container, project_id: project_id, id: id)

  @doc """
  The instances minted under `parent_container_id` at `parent_queue`,
  oldest first — how a parent's queue finds the child it is waiting on
  (§15.7's "the parent's queue does not complete until the minted
  instance closes").

  `nil` as the parent means the outermost instances: a project's own,
  minted from the workflow bundle's `entry:` type with nothing above
  it.
  """
  @spec child_containers(binary(), binary() | nil, String.t() | nil) :: [Container.t()]
  def child_containers(project_id, parent_container_id, parent_queue) do
    Container
    |> where([c], c.project_id == ^project_id)
    |> where_nilable(:parent_container_id, parent_container_id)
    |> where_nilable(:parent_queue, parent_queue)
    |> order_by([c], asc: c.minted_sequence, asc: c.id)
    |> Repo.all()
  end

  @doc "Records how one carried finding left. Idempotent on replay, like every other write here."
  @spec adjudicate_finding(map()) :: ContainerFinding.t()
  def adjudicate_finding(attrs) do
    %ContainerFinding{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(on_conflict: :nothing, conflict_target: [:project_id, :id])
  end

  @doc "Every finding this container has adjudicated, filed and declined alike."
  @spec container_findings(binary(), binary()) :: [ContainerFinding.t()]
  def container_findings(project_id, container_id) do
    ContainerFinding
    |> where([f], f.project_id == ^project_id and f.container_id == ^container_id)
    |> order_by([f], asc: f.adjudicated_sequence, asc: f.id)
    |> Repo.all()
  end

  @doc """
  The unresolved work items assigned to `queue` in `container_id` —
  **the queue itself, computed on every call** (dsl-syntax.md §15.7, v5
  §7.8).

  There is no bucket behind this and there is deliberately never going
  to be one: `ready_scopes` refuses to materialize for the identical
  reason, and `Catapult.Engine.Scheduler` holds no memory of what it
  last broadcast — a stale ordering is worse than none, because it is
  the kind of thing a dispatcher acts on.
  """
  @spec queue_population(binary(), binary(), String.t()) :: [Flow.t()]
  def queue_population(project_id, container_id, queue) do
    project_id
    |> queue_scope(container_id, queue)
    |> where([f], f.status == :open)
    |> order_by([f], asc: f.opened_sequence, asc: f.id)
    |> Repo.all()
  end

  @doc """
  Whether anything has **ever** been assigned to `queue` in
  `container_id`, resolved work included — the fact `singleton:`'s
  lifetime bound is checked against (dsl-syntax.md §15.7).

  This is not stored state reintroduced by the back door: it is
  `queue_population/3`'s own query with the resolution filter dropped.
  A `terminal` work item is invisible to the queue-as-query but not to
  the flow store it is one of, so the singleton check is one *fewer*
  predicate over the same table, not a new bucket.
  """
  @spec queue_ever_assigned?(binary(), binary(), String.t()) :: boolean()
  def queue_ever_assigned?(project_id, container_id, queue) do
    project_id |> queue_scope(container_id, queue) |> Repo.exists?()
  end

  @doc "Every work item this container holds, at any queue, resolved or not — a container's access path to its own work (v5 §7.8)."
  @spec container_work_items(binary(), binary()) :: [Flow.t()]
  def container_work_items(project_id, container_id) do
    Flow
    |> where([f], f.project_id == ^project_id and f.container_id == ^container_id)
    |> order_by([f], asc: f.opened_sequence, asc: f.id)
    |> Repo.all()
  end

  defp queue_scope(project_id, container_id, queue) do
    where(
      Flow,
      [f],
      f.project_id == ^project_id and f.container_id == ^container_id and f.queue == ^queue
    )
  end

  defp where_nilable(query, field, nil), do: where(query, [c], is_nil(field(c, ^field)))
  defp where_nilable(query, field, value), do: where(query, [c], field(c, ^field) == ^value)

  defp update_container(project_id, id, set) do
    Repo.update_all(
      from(c in Container, where: c.project_id == ^project_id and c.id == ^id),
      set: set
    )

    :ok
  end

  @doc """
  The findings recorded while `container` was the active container —
  the set "every carried finding leaves adjudicated" (v5 §7.8) is
  measured against.

  **The window is the container's own active span**, from its
  activation to its close (or to now, while it is still open),
  measured in draft-commit sequence. That is what "carried" means here
  and it is chosen over a structural walk deliberately: the
  alternative — reviews on drafts of nodes descended from this
  container's member work items — needs a recursive walk of
  `parent_node_id` that this projection has no other caller for, and
  it would still miss a finding raised against a node the container
  did not itself produce but was nonetheless open during. A close is
  answerable for what came up on its watch.

  Returns each review's own `findings` entries flattened, in draft
  order, deduplicated by finding id — one review re-run over the same
  draft raises the same finding again, and adjudicating it twice is
  the conflict the aggregate rejects.
  """
  @spec carried_findings(binary(), integer() | nil, integer() | nil) :: [map()]
  def carried_findings(project_id, from_sequence, to_sequence) do
    Review
    |> join(:inner, [r], d in Draft, on: d.project_id == r.project_id and d.id == r.draft_id)
    |> where([r, _d], r.project_id == ^project_id)
    |> then(&sequence_at_or_after(&1, from_sequence))
    |> then(&sequence_at_or_before(&1, to_sequence))
    |> order_by([_r, d], asc: d.committed_sequence)
    |> select([r, _d], r.findings)
    |> Repo.all()
    |> List.flatten()
    |> Enum.uniq_by(&finding_id/1)
  end

  # A container with no recorded activation carries everything before
  # it too — an unbounded window is the honest answer to "since when?"
  # when the answer is "we do not know," and it errs toward *more*
  # findings needing adjudication rather than fewer, which is the safe
  # direction for a check whose whole job is that nothing slips out
  # unread.
  defp sequence_at_or_after(query, nil), do: query

  defp sequence_at_or_after(query, sequence),
    do: where(query, [_r, d], d.committed_sequence >= ^sequence)

  defp sequence_at_or_before(query, nil), do: query

  defp sequence_at_or_before(query, sequence),
    do: where(query, [_r, d], d.committed_sequence <= ^sequence)

  defp finding_id(%{"id" => id}), do: id
  defp finding_id(%{id: id}), do: id
  defp finding_id(other), do: other

  @doc """
  Whether the work item `flow_id` still waits on an unresolved
  `:dependency` edge — the structured "cannot start yet" signal
  composition filters candidates against (v5 §7.8,
  `Catapult.Delivery.ContainerLifecycle.Composition`).

  Measured from the work item's own entry node outward: a dependency
  edge out of that node whose target is not yet `:approved` is work
  this item is waiting on. `false` for a work item with no entry node
  recorded, which is the honest answer — nothing is known to block it.
  """
  @spec blocking_edges_unresolved?(binary(), binary()) :: boolean()
  def blocking_edges_unresolved?(project_id, flow_id) do
    case Repo.get_by(Flow, project_id: project_id, id: flow_id) do
      %Flow{entry_node_id: entry_node_id} when not is_nil(entry_node_id) ->
        Edge
        |> join(:inner, [e], n in Node,
          on: n.project_id == e.project_id and n.id == e.target_node_id
        )
        |> where([e, _n], e.project_id == ^project_id and e.source_node_id == ^entry_node_id)
        |> where([e, _n], e.type == :dependency)
        |> where([_e, n], n.status != :approved)
        |> Repo.exists?()

      _absent_or_no_entry_node ->
        false
    end
  end
end
