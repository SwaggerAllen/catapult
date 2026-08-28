defmodule Catapult.Delivery.ContainerLifecycle do
  @moduledoc """
  The queue dispatcher (`systems/delivery.md`'s ORC-104 design pass; v5
  §7.8; dsl-syntax.md §15.6-§15.8): a Commanded process manager that
  decides *when* a container's position moves and issues the command,
  built beside `Catapult.Delivery.FeatureLifecycle` on the identical
  `application: Catapult.Engine.Application`-subscribed shape.

  **The first of this system's process managers that writes back.**
  `FeatureLifecycle` only projects engine's events into this system's
  own read models; this one also dispatches commands into
  `Catapult.Engine.Aggregate` once its own conditions are met. The
  split is the one `systems/engine.md` states from the other side —
  engine validates and records, this system decides — and it is new in
  direction only, not in kind.

  ## What it decides, and what it refuses to decide

  **Dispatch is uniform** (§15.7). What happens on entering a position
  follows from what the entry *is* — queue-shaped or not, agent-balled
  or not — never from anything the entry declares by name:

    * a queue-shaped `flow:` resolves to a type with a population
      anchor of its own → mint an instance and, since the parent's
      position is already here, activate it;
    * a queue-shaped `flow:` resolves to a type with none → the queue
      holds ordinary work items, and this dispatcher never invents
      them: a `prep` queue's population arrives by grooming, and a
      dispatcher that manufactured entries for it would be inventing
      scope;
    * a non-queue-shaped, non-critique agent-balled entry other than
      `merge` (`inline_dispatch_point?/1`) → open *the* one work item
      it ever holds, once (ORC-148's replacement for a retired
      `singleton: true` field — `setup` and `retro` are this module's
      motivating case, since neither carries `flow:` once folded
      directly into `milestone`'s own array).

  `retro` and `setup` are not special-cased **by name**: what makes the
  plane open *the* one work item for either is that each is a
  non-queue-shaped agent-balled entry, a declared fact about the
  entry's own shape, not the string `"setup"` or `"retro"`. **The one
  named exception is `merge`**, agent-balled like `setup`/`retro` but
  never a fresh dispatch point when it appears directly in a
  container's array — it is the *same* flow's own reconciliation step,
  owned by the chain-tier mechanism that already tracks a flow's
  internal generation-to-deploy progression — so `inline_dispatch_point?/1`
  excludes it by name rather than inventing a second declared field for
  a distinction the grammar leaves to a fixed kind. Nothing else in
  this module branches on the words `setup`, `retro`, `main`, `prep`,
  `cleanup`, `ticket`, `container` or `milestone`.

  **A queue holds while a sibling that blocks it carries work**
  (§15.7), and holds while any instance it minted is still open. Both
  live in `Catapult.Engine.Projections.ContainerQueues.resolution/3`,
  which is a query — this module reads it, and stores nothing.

  **A gate is where the plane stops.** Reaching a `review:` entry ends
  this dispatcher's turn: advancing past it is a human's command, with
  their actor recorded (v5 §7.16 — approval *is* the transition, there
  is no approval object). A milestone's two author transitions — the
  manual pass, and the read of `retro`'s proposals — are exactly this,
  which is why they need no bespoke command pair of their own and why
  a close is a sequence of states rather than a button.

  **Nothing closes over an unadjudicated finding.** A container does
  not reach `terminal` while any finding it carried lacks a filing or a
  recorded decline (v5 §7.8). `systems/delivery.md`'s design pass
  frames this as `retro`'s completion gate; it is enforced here at the
  close instead, and deliberately: attaching it to a queue would mean
  recognizing that queue by name, which is precisely the implicit
  anchor meaning above. Attaching it to the close says the same thing
  about the same container without asking the grammar for a magic word
  — and says it about every container, including one whose author
  declared no backward-looking queue at all.

  ## The two backward moves

  Both of §15.8's are honoured, and neither needs an event of its own:

    * **repopulated** — a resolved queue un-resolves when its
      population refills. Since a queue is a query, this is just
      `resolution/3` answering differently after a `FlowOpened`, and
      this module reacts by moving the position back to the earliest
      unresolved queue.
    * **throwback** — a gate the container's own array cites rejects to
      an earlier entry. That is a human's `AdvanceContainerQueue` with
      `reason: :throwback`, not something this module originates;
      `Catapult.Delivery.ContainerLifecycle.Sequence.earlier?/4` is the
      live half of the check the loader can only make statically.

  ## Why it dispatches itself instead of returning commands

  A Commanded process manager ordinarily returns commands and lets its
  `application:` route them. That is not available here, and for a
  reason this codebase chose deliberately:
  `Catapult.Engine.Application` does not compose
  `Catapult.Engine.Router` (that module's own moduledoc explains why —
  keeping the router off the compile-connected graph), so a returned
  command is an *unregistered* command and Commanded stops the manager.
  `handle/2` therefore dispatches through `Catapult.Engine.Router`
  itself and returns `[]`.

  Two consequences worth stating rather than discovering:

  * **`consistency: :eventual`, never `:strong`.** A strongly
    consistent dispatch waits for every strongly consistent handler to
    catch up — including this one — so dispatching `:strong` from
    inside its own `handle/2` is a deadlock against itself. The
    resulting events come back around to this manager, which
    re-evaluates; that loop *is* the convergence.
  * **A rejected command is absorbed, not fatal.** Commanded's default
    error handling stops a manager whose command was refused, which is
    wrong for exactly the rejections this design produces on purpose: a
    stale `from_queue` losing a compare-and-swap, or a re-mint of an
    instance that already exists, are both this manager re-deriving a
    decision that has already been made. Those are logged at debug and
    the manager carries on; anything else is logged as a warning.

  ## Known Phase 4 limitation, named rather than hidden

  This module reads populations from `Catapult.Engine.Store`, written
  by `Catapult.Engine.Projector` — a *different* subscription. Both are
  `consistency: :strong`, but that orders each subscriber against its
  own dispatcher, not against each other, so a decision taken here can
  read a projection one event stale. Three things make that safe rather
  than merely tolerated, and the third is why no sweeper is added here:
  every command this module issues carries a compare-and-swap
  (`from_queue`), so a stale decision is *rejected*, not applied; the
  module re-evaluates on every event that could change an answer, so a
  rejected decision is retaken; and Phase 7's own convergence machinery
  is where a periodic floor belongs, beside the rest of the two-grain
  delivery machinery, not bolted on here. `FeatureLifecycle` carries
  the same shape and says so for the same reason.

  **`@derive Jason.Encoder` and the `JsonDecoder` implementation below**
  (ORC-120, folded in from a separate carried finding against the
  identical defect `Catapult.Delivery.FeatureLifecycle` was found with):
  `Commanded.ProcessManagers.ProcessManagerInstance` persists this
  struct through `Commanded.Serialization.JsonSerializer` the same
  unconditional way it does `FeatureLifecycle`'s, and without an
  encoder that crashes real (non-`InMemory`) persistence on the first
  write. Unlike `FeatureLifecycle`, no field here is a raw
  `Sequence.position()`-shaped tuple — `type_name` and `queue` are both
  `String.t() | nil` — so `@derive` alone is the whole of the encode
  half. `state` is an atom (`:minted | :active | :closed`), which
  `Jason` encodes to a JSON string and `struct/2` then restores as that
  bare string rather than reconstructing the atom, in violation of this
  struct's own `@type` — the `JsonDecoder` implementation below is
  exactly `String.to_existing_atom/1` on the way back, safe for the
  same reason it is everywhere else in this system: the three values
  are compile-time literals in this module already, so they are
  already in the atom table before any snapshot is ever read.
  """

  use Commanded.ProcessManagers.ProcessManager,
    application: Catapult.Engine.Application,
    name: :delivery_container_lifecycle,
    consistency: :strong

  require Logger

  alias Catapult.Config
  alias Catapult.Delivery.ContainerLifecycle.Composition
  alias Catapult.Delivery.ContainerLifecycle.Ids
  alias Catapult.Delivery.ContainerLifecycle.Sequence
  alias Catapult.Delivery.FlagSetWorker
  alias Catapult.Dsl
  alias Catapult.Dsl.Status
  alias Catapult.Dsl.Workflow
  alias Catapult.Engine.Commands.ActivateContainer
  alias Catapult.Engine.Commands.AdvanceContainerQueue
  alias Catapult.Engine.Commands.CloseContainer
  alias Catapult.Engine.Commands.MintContainer
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Commands.RequestFlagSetFlip
  alias Catapult.Engine.Events.ContainerActivated
  alias Catapult.Engine.Events.ContainerClosed
  alias Catapult.Engine.Events.ContainerMinted
  alias Catapult.Engine.Events.ContainerQueueAdvanced
  alias Catapult.Engine.Events.FindingAdjudicated
  alias Catapult.Engine.Events.FlagSetFlipRequested
  alias Catapult.Engine.Events.FlowCompleted
  alias Catapult.Engine.Events.FlowOpened
  alias Catapult.Engine.Projections.ContainerQueues
  alias Catapult.Engine.Router
  alias Catapult.Engine.Store, as: EngineStore
  alias Catapult.Engine.Store.Container

  @enforce_keys [:project_id, :container_id]
  @derive Jason.Encoder
  defstruct [:project_id, :container_id, :type_name, :queue, state: :minted]

  @type t :: %__MODULE__{
          project_id: binary(),
          container_id: binary(),
          type_name: String.t() | nil,
          queue: String.t() | nil,
          state: :minted | :active | :closed
        }

  ## Routing

  def interested?(%ContainerMinted{} = event) do
    {:start, identity(event.project_id, event.container_id)}
  end

  def interested?(%ContainerActivated{} = event) do
    {:continue, identity(event.project_id, event.container_id)}
  end

  def interested?(%ContainerQueueAdvanced{} = event) do
    {:continue, identity(event.project_id, event.container_id)}
  end

  def interested?(%FindingAdjudicated{} = event) do
    {:continue, identity(event.project_id, event.container_id)}
  end

  def interested?(%FlagSetFlipRequested{} = event) do
    {:continue, identity(event.project_id, event.container_id)}
  end

  def interested?(%ContainerClosed{} = event) do
    {:stop, identity(event.project_id, event.container_id)}
  end

  # A work item's own container membership is what routes it here: a
  # flow opening into or completing out of a queue is the one thing
  # that can change a population, and a population is what every
  # resolution answer is built on.
  def interested?(%FlowOpened{container_id: nil}), do: false

  def interested?(%FlowOpened{} = event) do
    {:continue, identity(event.project_id, event.container_id)}
  end

  # `FlowCompleted` carries no container of its own, so membership is
  # resolved from the flow record the projector already wrote — the
  # same "read engine's own state of record rather than assume"
  # `FeatureLifecycle` does for its own routing.
  def interested?(%FlowCompleted{} = event) do
    case EngineStore.get_flow(event.project_id, event.flow_id) do
      %{container_id: container_id} when not is_nil(container_id) ->
        {:continue, identity(event.project_id, container_id)}

      _absent_or_unowned ->
        false
    end
  end

  def interested?(_event), do: false

  defp identity(project_id, container_id), do: project_id <> ":" <> container_id

  ## State — every field is folded from an event this manager already
  ## subscribes to, so the position it reasons about is never a read
  ## that can be stale (see the moduledoc's limitation note, which is
  ## scoped to populations alone).

  def apply(%__MODULE__{} = pm, %ContainerMinted{} = event) do
    %{
      pm
      | project_id: event.project_id,
        container_id: event.container_id,
        type_name: event.type_name,
        state: :minted
    }
  end

  def apply(%__MODULE__{} = pm, %ContainerActivated{} = event) do
    %{pm | state: :active, queue: event.queue}
  end

  def apply(%__MODULE__{} = pm, %ContainerQueueAdvanced{} = event) do
    %{pm | queue: event.to_queue}
  end

  def apply(%__MODULE__{} = pm, %ContainerClosed{}), do: %{pm | state: :closed}

  ## Dispatch

  def handle(%__MODULE__{} = pm, event)
      when is_struct(event, ContainerActivated)
      when is_struct(event, ContainerQueueAdvanced)
      when is_struct(event, FlowOpened)
      when is_struct(event, FlowCompleted)
      when is_struct(event, FindingAdjudicated) do
    dispatch_next(pm)
  end

  def handle(%__MODULE__{} = pm, %FlagSetFlipRequested{} = event) do
    FlagSetWorker.enqueue(event.project_id, event.container_id, event.request_id, event.flags)
    dispatch_next(pm)
  end

  def handle(%__MODULE__{}, _event), do: []

  defp dispatch_next(%__MODULE__{} = pm) do
    with {:ok, workflow} <- load_workflow(),
         %Container{} = container <- EngineStore.get_container(pm.project_id, pm.container_id) do
      workflow |> next_commands(container) |> dispatch_all()
    else
      _unloadable_or_absent -> []
    end
  end

  # See the moduledoc: `:eventual`, and rejections absorbed.
  defp dispatch_all(commands) do
    Enum.each(commands, fn command ->
      case Router.dispatch(command, consistency: :eventual) do
        :ok -> :ok
        {:error, reason} -> log_rejection(command, reason)
      end
    end)

    []
  end

  # The rejections this design produces on purpose: this manager
  # re-derived a decision that has already been made. Not errors, and
  # certainly not grounds to stop the manager.
  defp log_rejection(command, {kind, _details} = reason)
       when kind in [
              :engine_container_exists,
              :engine_container_queue_conflict,
              :engine_container_not_activatable,
              :engine_container_not_active,
              :engine_flag_flip_already_requested
            ] do
    Logger.debug(
      "container lifecycle command already settled: #{inspect(reason)} for #{inspect(command)}",
      component: :delivery
    )
  end

  defp log_rejection(command, reason) do
    Logger.warning(
      "container lifecycle command refused: #{inspect(reason)} for #{inspect(command)}",
      component: :delivery
    )
  end

  @doc """
  What this dispatcher would issue for `container` right now, given
  `workflow` — the whole decision, in one synchronous function.

  Public on purpose. The process manager above is a thin subscriber
  that calls this and dispatches the result, which is what makes the
  decision testable without driving an asynchronous cascade and
  waiting on it (conventions §9: test determinism is a protocol
  requirement, and a suite that sleeps to observe a convergence loop is
  the flaky kind the escalation rules cannot afford).

  The order of the questions matters and is not arbitrary:

  1. **Has an earlier queue refilled?** Then the container is no longer
     past it and the position moves back (§15.8's first backward move).
     This is asked first because a container standing somewhere it
     should not be must not start work there.
  2. **Is the current queue held by a sibling that `blocks:` it?** Then
     nothing begins. "`retro` will not begin until it clears" (v5 §7.8)
     is this: a blocked queue does not open its work item, which is the
     whole content of the hold.
  3. **Does entering the current position put work into it?** A queue
     whose `flow:` nests mints — once — and activates a child; a
     non-queue-shaped inline dispatch point (`inline_dispatch_point?/1`)
     opens its one work item. If either produced a command, the
     position is about to be non-empty and there is nothing to advance
     past yet.
  4. **Otherwise, where does the position move forward to?** The next
     entry if the current one resolves, nowhere at all if it does not
     or if the next entry is a gate waiting on a human.

  Returns `[]` for anything not currently active: a merely minted
  instance is not running yet, and a closed one is done.
  """
  @spec next_commands(Workflow.t(), Container.t()) :: [struct()]
  def next_commands(%Workflow{} = workflow, %Container{state: :active} = container) do
    steps = Sequence.steps(workflow, container.type_name)
    current = container.current_queue

    case earliest_unresolved(workflow, container, steps, current) do
      target when not is_nil(target) and target != current ->
        [advance(container, current, target, :repopulated)]

      _settled_behind ->
        forward_or_open(workflow, container, current)
    end
  end

  def next_commands(%Workflow{}, %Container{}), do: []

  defp forward_or_open(%Workflow{} = workflow, %Container{} = container, current) do
    case ContainerQueues.resolution(workflow, container, current) do
      # Held by a sibling that blocks it. Nothing begins here — not
      # even an inline dispatch point's own work item, which is what
      # "retro will not begin until it clears" actually means (v5 §7.8).
      {:held, _holders} ->
        []

      :resolved ->
        case open_work(workflow, container) do
          [] -> forward(workflow, container, current)
          commands -> commands
        end

      :open ->
        open_work(workflow, container)
    end
  end

  # Entering a queue is where dispatch happens, and it is uniform: what
  # to do follows from the *resolved* declaration, never from the queue
  # entry (§15.7).
  defp open_work(%Workflow{} = workflow, %Container{} = container) do
    case Sequence.step(workflow, container.type_name, container.current_queue) do
      {:queue, entry} -> open_for(workflow, container, entry)
      _gate_or_terminal_or_unknown -> []
    end
  end

  # The declaration decides whether there is anything for the plane
  # itself to open here:
  #
  #   * a queue-shaped `flow:` target — mint the child instance and
  #     activate it, since the parent's position is already here
  #     (§15.8: mint is what creates, reaching it is what activates);
  #   * a non-queue-shaped inline dispatch point (`setup`/`retro`,
  #     ORC-148 — no `flow:` left to mint a child through) — open *the*
  #     one work item, once and never again;
  #   * anything else — nothing. Ordinary ticket work arrives by
  #     grooming, and manufacturing it would be inventing scope.
  defp open_for(%Workflow{} = workflow, %Container{} = container, %Status{} = entry) do
    cond do
      nests?(workflow, entry) -> mint_child(workflow, container, entry)
      inline_dispatch_point?(entry) -> open_inline(workflow, container, entry)
      true -> []
    end
  end

  defp nests?(%Workflow{types: types}, %Status{flow: flow}) do
    case Map.fetch(types, flow) do
      {:ok, type} -> type.skeleton in [nil, "container"]
      :error -> false
    end
  end

  # A non-queue-shaped entry (no `flow:`, so it cannot mint a child)
  # that opens a fresh flow instance the moment the container's
  # position reaches it — ORC-148's replacement for a `singleton: true`
  # queue, now that `setup`/`retro` fold directly into `milestone`'s
  # own array with no `flow:` to represent them. Scoped to
  # `Status.non_critique_agent_step?/1`'s set minus `merge`: `merge` is
  # agent-balled too (§15.1's `ball` column), but when it appears
  # directly in a container's array — `setup`'s and `retro`'s own
  # checks/merge/deploy sequence, ORC-148, dsl-syntax.md §15.2 — it is
  # the *same* flow's own reconciliation step, tracked by the chain-tier
  # mechanism that already owns a flow's internal generation-to-deploy
  # progression, never a fresh thing for this dispatcher to open.
  defp inline_dispatch_point?(%Status{status: status} = entry) do
    not Status.queue_shaped?(entry) and Status.non_critique_agent_step?(entry) and
      status != "merge"
  end

  # Three cases, and the third is the one a naive "is there an
  # unactivated child?" check gets wrong: an *active* child means this
  # queue is already running its instance, so minting a second
  # alongside it would fork the queue. Only a queue with no child at
  # all mints.
  defp mint_child(%Workflow{} = workflow, %Container{} = container, %Status{} = entry) do
    children = EngineStore.child_containers(container.project_id, container.id, entry.status)

    case Enum.find(children, &(&1.state == :minted)) do
      # Already groomed into existence before the parent's position
      # reached it — the case §15.8 exists for. Activate what is there.
      %Container{} = child ->
        [
          %ActivateContainer{
            project_id: container.project_id,
            container_id: child.id,
            queue: first_queue_name(workflow, child.type_name)
          }
        ]

      nil when children != [] ->
        []

      nil ->
        [
          %MintContainer{
            project_id: container.project_id,
            container_id: Ids.container_id(container.project_id, container.id, entry.status),
            type_name: entry.flow,
            parent_container_id: container.id,
            parent_queue: entry.status
          }
        ]
    end
  end

  defp first_queue_name(%Workflow{} = workflow, type_name) do
    case Sequence.first_step(workflow, type_name) do
      nil -> "terminal"
      step -> Sequence.name(step)
    end
  end

  # `ContainerQueues.admits?/3`'s lifetime bound asks "has anything
  # *ever* been assigned," not "is anything unresolved now" (§15.7). A
  # closed inline dispatch point stays closed: that is what running
  # once, at this one array position, means, and there is no escape
  # hatch to add. `flow_name` names no declared type — an inline entry
  # carries no `flow:` for one to resolve — so it is the entry's own
  # name, addressed the same way `queue` already is.
  defp open_inline(%Workflow{} = workflow, %Container{} = container, %Status{} = entry) do
    case ContainerQueues.admits?(workflow, container, entry.status) do
      {:ok, _entry} ->
        flow_id = Ids.work_item_id(container.project_id, container.id, entry.status)

        [
          %OpenFlow{
            project_id: container.project_id,
            flow_id: flow_id,
            flow_name: entry.status,
            entry_node_id: flow_id,
            container_id: container.id,
            queue: entry.status
          }
        ]

      {:error, :singleton_closed} ->
        # Loud, per §15.7: a second assignment to a one-shot inline
        # entry, ever, is an error rather than an admitted dispatch that
        # files `Blocked` the way an unrecognized `flow:` label does.
        # This dispatcher re-enters on every relevant event, so the
        # ordinary path here is the entry simply having done its job;
        # the log line is what makes a genuine second attempt visible
        # rather than silently absorbed.
        Logger.debug(
          "inline dispatch point #{inspect(entry.status)} on container #{container.id} is " <>
            "closed and admits no further work (dsl-syntax.md §15.7)",
          component: :delivery
        )

        []

      {:error, :unknown_queue} ->
        []
    end
  end

  ## Where the position goes next.

  defp forward(%Workflow{} = workflow, %Container{} = container, current) do
    case Sequence.next_step(workflow, container.type_name, current) do
      # No next entry: a skeleton-less instance closing on its own last
      # declared entry resolving with nothing open behind it (§15.6). A
      # container-skeleton instance never lands here — its array ends at
      # `terminal`, which is a step.
      nil ->
        close(workflow, container)

      :terminal ->
        close(workflow, container)

      # Where the plane stops. Advancing past a gate is a human's
      # command, recorded with their actor.
      {:gate, _name} ->
        []

      {:queue, entry} ->
        [advance(container, current, entry.status, :resolved)]
    end
  end

  # Closing is the one transition with preconditions of its own beyond
  # the queue model: every carried finding adjudicated, and the
  # aggregated flag set requested (v5 §7.8). Both are computed here and
  # neither is stored — the outstanding set is a difference of two
  # queries, and the flag set is a union of what the members declare.
  defp close(%Workflow{} = workflow, %Container{} = container) do
    case outstanding_findings(container) do
      [] ->
        Composition.propose(workflow, container, sequence: container.current_queue_sequence)

        flip_commands(container) ++
          [%CloseContainer{project_id: container.project_id, container_id: container.id}]

      outstanding ->
        Logger.info(
          "container #{container.id} holds #{length(outstanding)} unadjudicated finding(s) " <>
            "and will not close over them (v5 §7.8)",
          component: :delivery
        )

        []
    end
  end

  # The findings this container carried, minus the ones it recorded an
  # outcome for. A finding with no record has not been read, which is
  # exactly the state a close may not resolve over.
  defp outstanding_findings(%Container{} = container) do
    adjudicated =
      container.project_id
      |> EngineStore.container_findings(container.id)
      |> MapSet.new(& &1.id)

    container.project_id
    |> EngineStore.carried_findings(container.activated_sequence, container.closed_sequence)
    |> Enum.reject(&MapSet.member?(adjudicated, finding_id(&1)))
  end

  defp finding_id(%{"id" => id}), do: id
  defp finding_id(%{id: id}), do: id
  defp finding_id(other), do: other

  # The union of the flags this container's member work items
  # registered — "features merge dark as they complete; the milestone
  # lights up together" (v5 §7.8). Requested once, and only where there
  # is not already a request on the record: the aggregate admits one
  # intent, so re-requesting is a rejection rather than a second flip.
  defp flip_commands(%Container{flag_set_state: :none} = container) do
    [
      %RequestFlagSetFlip{
        project_id: container.project_id,
        container_id: container.id,
        request_id: Ids.flag_request_id(container.project_id, container.id),
        flags: aggregated_flags(container)
      }
    ]
  end

  defp flip_commands(%Container{}), do: []

  defp aggregated_flags(%Container{} = container) do
    container.project_id
    |> EngineStore.container_work_items(container.id)
    |> Enum.flat_map(&work_item_flags/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # A work item's flags are the ones the components it produced declare
  # in `feature_flags/0` (v5 §2.10). Nothing in this tree declares one
  # yet — conventions §13 defers flag consumption — so today this is
  # empty for every project, and `Catapult.Delivery.FlagSet.Deferred`
  # enables an empty set successfully rather than holding a milestone
  # open over a no-op. The seam is here so that the day a flag is
  # declared, nothing above this line changes.
  defp work_item_flags(_flow), do: []

  defp advance(%Container{} = container, from, to, reason) do
    %AdvanceContainerQueue{
      project_id: container.project_id,
      container_id: container.id,
      from_queue: from,
      to_queue: to,
      reason: reason
    }
  end

  defp resolved_here?(%Workflow{} = workflow, %Container{} = container, queue) do
    ContainerQueues.resolution(workflow, container, queue) == :resolved
  end

  # The earliest queue before `current` that is no longer resolved.
  # `nil` when everything behind the container is still settled, which
  # is the ordinary case.
  defp earliest_unresolved(%Workflow{} = workflow, %Container{} = container, steps, current) do
    steps
    |> Enum.take_while(&(Sequence.name(&1) != current))
    |> Enum.find_value(fn
      {:queue, entry} ->
        if resolved_here?(workflow, container, entry.status), do: nil, else: entry.status

      _gate_or_terminal ->
        nil
    end)
  end

  defp load_workflow do
    case Dsl.load(Config.fetch!(:engine, :bundles_root)) do
      {:ok, %{workflow: %Workflow{} = workflow}} ->
        {:ok, workflow}

      {:ok, %{workflow: nil}} ->
        {:error, :no_workflow_bundle}

      {:error, reason} = error ->
        Logger.warning(
          "container lifecycle skipped a dispatch: bundle unloadable (#{inspect(reason)})",
          component: :delivery
        )

        error
    end
  end
end

defimpl Commanded.Serialization.JsonDecoder, for: Catapult.Delivery.ContainerLifecycle do
  alias Catapult.Delivery.ContainerLifecycle

  @doc "See `ContainerLifecycle`'s own moduledoc entry: reconstructs the atom `struct/2` leaves as a bare string after `JsonSerializer.deserialize/2`'s round trip."
  def decode(%ContainerLifecycle{state: state} = pm) when is_binary(state) do
    %{pm | state: String.to_existing_atom(state)}
  end

  def decode(%ContainerLifecycle{} = pm), do: pm
end
