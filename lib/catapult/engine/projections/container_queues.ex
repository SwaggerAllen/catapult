defmodule Catapult.Engine.Projections.ContainerQueues do
  @moduledoc """
  A container's queues, computed on every call (dsl-syntax.md
  §15.6-§15.8, v5 §7.8) — the same "pure query against current
  projections rather than a maintained table" shape
  `Catapult.Engine.Projections.ReadyScopes` already establishes, one
  level up from the chain axis.

  **A queue is a query, never stored.** The population of a declared
  queue is "the unresolved work items in this container assigned to
  it," answered from `engine_flows`'s own `container_id`/`queue`
  columns. Nothing writes a per-queue bucket and nothing reads one
  back, for the reason v5 §1.2 and §7.8 both give and this codebase
  has already acted on twice — `ready_scopes` refuses to materialize,
  and `Catapult.Engine.Scheduler` holds no memory of what it last
  broadcast: a stale ordering is worse than none, because it is
  precisely the kind of thing a dispatcher acts on.

  **The loaded workflow is a parameter, never resolved here.** Same
  discipline as `ReadyScopes.ready/3` and
  `Catapult.Engine.Scheduler.trigger/2`: the caller
  (`Catapult.Delivery.ContainerLifecycle`) resolves which bundle is
  active and hands the loaded `Catapult.Dsl.Workflow.t()` in.

  Two facts this module deliberately does *not* answer, because they
  are the dispatcher's rather than the state of record's: whether a
  work item may be opened into a queue (a one-shot inline agent step's
  own lifetime bound, ORC-148's replacement for the retired
  `singleton:` field — `admits?/3` reports the state, `Catapult
  .Delivery.ContainerLifecycle` decides what to do about it), and which
  queue comes next after a throwback (that is the citing type's own
  array, read against the gate's declared `throwback:` or the default
  `Catapult.Dsl.Workflow.throwback_default/3` derives for it).
  """

  alias Catapult.Dsl.Status
  alias Catapult.Dsl.Type
  alias Catapult.Dsl.Workflow
  alias Catapult.Engine.Store
  alias Catapult.Engine.Store.Container

  @typedoc """
  What a single declared entry currently resolves to.

  `:resolved` and `:open` are the two states the queue model has;
  `:held` is `:open`'s reason rather than a third state, carrying the
  sibling queues whose `blocks:` relation names this one and which
  still hold unresolved work (§15.6's "no separate blocked anchor
  kind, and none is missing").
  """
  @type resolution :: :resolved | :open | {:held, [String.t()]}

  @doc """
  The declared `statuses:` entries of `container`'s own type, in array
  order — the only ordering mechanism this grammar has (§15.3).

  Returns `[]` when the container's recorded `type_name` does not
  resolve in `workflow`. That is not an error to raise: a workflow
  cutover can retire a type out from under a live instance, and the
  caller's answer is to leave the container where it stands rather
  than to crash the projector.
  """
  @spec entries(Workflow.t(), Container.t()) :: [Status.t()]
  def entries(%Workflow{types: types}, %Container{type_name: type_name}) do
    case Map.fetch(types, type_name) do
      {:ok, %Type{statuses: statuses}} -> statuses
      :error -> []
    end
  end

  @doc """
  The unresolved work items assigned to `queue` in this container.

  Computed, every call. See the moduledoc for why there is no bucket
  behind it.
  """
  @spec population(Container.t(), String.t()) :: [Store.Flow.t()]
  def population(%Container{} = container, queue) do
    Store.queue_population(container.project_id, container.id, queue)
  end

  @doc """
  Every queue-shaped entry's population, keyed by queue name — the
  whole container at once, for a caller that would otherwise call
  `population/2` in a loop.
  """
  @spec populations(Workflow.t(), Container.t()) :: %{String.t() => [Store.Flow.t()]}
  def populations(%Workflow{} = workflow, %Container{} = container) do
    workflow
    |> entries(container)
    |> Enum.filter(&Status.queue_shaped?/1)
    |> Map.new(fn entry -> {entry.status, population(container, entry.status)} end)
  end

  @doc """
  How `queue` currently resolves in this container — see
  `t:resolution/0`.

  Three things have to be true for `:resolved`, and each is a rule the
  grammar states rather than a convenience:

    1. **Its own population is empty** (§15.7). A queue is a query, so
       a resolved queue un-resolves the moment its population refills,
       with no separate "went backward" event needed — which is
       §15.8's first of two backward moves, falling out of this
       function rather than being implemented anywhere.
    2. **Every container instance it minted has closed** (§15.7's "the
       parent's queue does not complete until the minted instance
       closes"). Nesting composes through this one completion rule; a
       queue whose `flow:` resolves to a ticket-skeleton type simply
       has no child instances, so the clause costs it nothing.
    3. **No sibling that `blocks:` it still holds unresolved work**
       (§15.7). Blocks are scoped to siblings by the loader, so this
       never reaches into a nested container's internals — doing so
       would make that container's internals part of its interface,
       exactly backwards from composability.

  A `review:` gate citation, an `environment:`, or `terminal` is never
  `:resolved` by this function: a gate is resolved by a human's
  transition, not by a population emptying, and reporting `:open` for
  one is what keeps the dispatcher from advancing past a human (v5
  §7.8's two irreducible author transitions). A non-queue-shaped
  `status:` entry — an inline one-shot agent step (`setup`/`retro`,
  ORC-148) or a fixed world/agent kind interleaved in the array
  (`checks`/`merge`/`deploy`/`pending`) — resolves the identical way a
  population anchor does: its own population (keyed by entry name,
  regardless of whether it carries `flow:`) is what a work item opened
  against it is tracked under.
  """
  @spec resolution(Workflow.t(), Container.t(), String.t()) :: resolution()
  def resolution(%Workflow{} = workflow, %Container{} = container, queue) do
    entries = entries(workflow, container)

    case Enum.find(entries, &positioned_entry?(&1, queue)) do
      nil ->
        :open

      entry ->
        cond do
          population(container, queue) != [] -> :open
          not children_closed?(container, queue) -> :open
          true -> held_or_resolved(container, entries, entry)
        end
    end
  end

  # Any `status:` entry a container's own position may rest at —
  # `Status.queue_shaped?/1`'s population anchors and the inline
  # one-shot agent steps alike (`setup`/`retro`, ORC-148), which carry
  # no `flow:` and so are not queue-shaped, but are still addressed by
  # name the identical way. `terminal` is excluded: it is a fixed end
  # kind a container *reaches*, never a position resolution is asked
  # about (§15.6).
  defp positioned_entry?(%Status{status: status}, queue) when status not in [nil, "terminal"],
    do: status == queue

  defp positioned_entry?(%Status{}, _queue), do: false

  @doc """
  Whether `queue` is resolved — `resolution/3` collapsed to a boolean
  for the common call.
  """
  @spec resolved?(Workflow.t(), Container.t(), String.t()) :: boolean()
  def resolved?(%Workflow{} = workflow, %Container{} = container, queue) do
    resolution(workflow, container, queue) == :resolved
  end

  @doc """
  Whether a work item may be opened into `queue` — `{:ok, entry}`, or
  `{:error, :singleton_closed}` when `queue` names a non-queue-shaped
  positioned entry (an inline one-shot agent step, ORC-148's
  `singleton:`-field replacement) and something has already been
  assigned to it.

  **The bound is over the entry's whole lifetime, not its momentary
  population** (§15.7's sixth-pass correction, restated after
  `singleton:`'s own retirement). Once a one-shot entry's one work item
  reaches `terminal` the query is empty again, and that emptiness is
  *closure*, not room: a population-scoped check would read it as an
  opening and admit a second. `retro` and `setup` are the motivating
  cases — a single work item moving through a flow once, ever — and
  this is what lets the dispatcher address *the* retro work item
  directly rather than iterating a set that structurally never holds
  more than one. A queue-shaped entry (`flow:` present) carries no such
  bound: it is an ordinary open-ended queue.

  Not a load-time check, and it could not be: assignment history is
  live ticket state, unknowable when a bundle loads (§13).
  """
  @spec admits?(Workflow.t(), Container.t(), String.t()) ::
          {:ok, Status.t()} | {:error, :unknown_queue | :singleton_closed}
  def admits?(%Workflow{} = workflow, %Container{} = container, queue) do
    entries = entries(workflow, container)

    case Enum.find(entries, &positioned_entry?(&1, queue)) do
      nil ->
        {:error, :unknown_queue}

      entry ->
        # A population anchor (`flow:` present) is an ordinary
        # open-ended queue with no lifetime bound; a non-queue-shaped
        # positioned entry is a one-shot inline agent step (`setup`,
        # `retro`, ORC-148 — no `flow:` left to represent it) and gets
        # the "at most once, ever" bound the retired `singleton:` field
        # used to carry explicitly.
        if Status.queue_shaped?(entry) or
             not Store.queue_ever_assigned?(container.project_id, container.id, queue) do
          {:ok, entry}
        else
          {:error, :singleton_closed}
        end
    end
  end

  # §15.7: a `blocks:` entry names sibling queues in the same array
  # whose completion it holds open while *this* queue carries
  # unresolved work. Read from the blocking side — "who names me" —
  # since that is the direction the dispatcher asks in.
  defp held_or_resolved(container, entries, %Status{status: queue}) do
    holders =
      for blocker <- entries,
          Status.queue_shaped?(blocker),
          queue in blocker.blocks,
          population(container, blocker.status) != [] or
            not children_closed?(container, blocker.status),
          do: blocker.status

    if holders == [], do: :resolved, else: {:held, holders}
  end

  # A queue whose `flow:` opened container instances does not complete
  # until each has closed (§15.7). A ticket-shaped queue has none, so
  # this is vacuously true for it — the uniformity §15.7 asks for,
  # rather than a branch on what the queue entry declares.
  defp children_closed?(%Container{} = container, queue) do
    container.project_id
    |> Store.child_containers(container.id, queue)
    |> Enum.all?(&(&1.state == :closed))
  end
end
