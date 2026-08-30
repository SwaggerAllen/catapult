defmodule Catapult.Delivery.FeatureLifecycle do
  @moduledoc """
  The author's state lever, in code (v5 §7.10, `systems/delivery.md`'s
  ORC-32 design pass): a Commanded process manager reading engine's own
  events and projecting the feature-ticket lifecycle — `pending →
  generation → [critique] → [gate] → … → checks`
  (`Catapult.Delivery.FeatureLifecycle.Sequence`) — into
  `Catapult.Delivery.Store`'s own read model, which the work surface
  renders. No third-party tracker in this path (v5 §7.17).

  `application: Catapult.Engine.Application`-subscribed — the events
  this reacts to (`FlowOpened`, `DraftCommitted`, `RunFailed`) are
  engine's own, and this application already carries every other
  reactive subscriber over the same stream
  (`Catapult.Engine.Projector`). `consistency: :strong` for the same
  reason `Catapult.Engine.Projector` uses it: a caller dispatching with
  `consistency: :strong` (the ordinary case at every call site today)
  reads this projection back synchronously, not eventually.

  **Identity is the pair `(project_id, flow_id)`, composited, never a
  bare id** (ORC-87, `systems/delivery.md`): `project_id <> ":" <>
  flow_id`. A `DraftCommitted`/`RunFailed` carries no `flow_id` of its own, so
  routing one to an existing instance resolves the project's current
  open flow (`Catapult.Delivery.Store.current_open_flow_id/1`, itself a
  read of engine's own `engine_flows` — state of record,
  `systems/delivery.md`'s "Depends on" list) rather than assuming a bare
  `project_id` is enough. **A Phase 4 simplification, named rather than
  hidden**: Phase 4 has no dispatch or mutex machinery yet, so this
  resolves to "the most recently opened, still-open flow" — correct
  today because nothing yet opens two flows concurrently on one
  project, not because this module has solved that case.

  **The loaded workflow is a parameter of the pure projection
  functions, never resolved by them** (`systems/delivery.md`): this
  module resolves `Catapult.Dsl.load/1` itself — the identical
  "resolve per event, from `ENGINE_BUNDLES_ROOT`, log and skip on
  failure" shape `Catapult.Engine.Projector`'s own fast path already
  takes, since which bundle is active for a project is a
  not-yet-built concern neither module may guess at
  (`systems/engine.md`) — and hands the loaded
  `Catapult.Dsl.Workflow.t()` to `Catapult.Delivery.FeatureLifecycle
  .Projection.resting/2` and `.block/2`. Those two functions, and
  `Sequence.positions/1` underneath them, never call the loader
  themselves.

  **Entry tier and the entry-tier skip rule are out of this module's
  reach today, named rather than silently dropped.** §7.3's rule
  narrows which positions are reachable for a given ticket type by its
  declared entry tier; resolving *which tier* a flow's entry node names
  needs the chain axis (`Catapult.Dsl.Chain`), which is not a parameter
  this ticket's design gives this process manager (only the loaded
  workflow is — see above). `entry_node_id` is recorded from
  `FlowOpened` and persisted for a later pass to build on; the skip
  rule itself is not implemented here.

  **`@derive Jason.Encoder` and the `JsonDecoder` implementation below**
  (ORC-120): `Commanded.ProcessManagers.ProcessManagerInstance` calls
  `persist_state/2` after every handled event, unconditionally, which
  round-trips this struct through `Commanded.Serialization
  .JsonSerializer` the identical way every event here already does —
  and without an encoder, `Jason.encode!/1` raises on the first write
  against a real (non-`InMemory`) event store, not on `mix test`
  (`config/test.exs`'s adapter never serializes state at all). Encoding
  the nested `projection` field is `Projection`'s own `Jason.Encoder`
  implementation's job (see its moduledoc); decoding it back is not —
  `JsonSerializer.deserialize/2` builds this struct via `struct/2`
  before any decoder protocol runs, which leaves `projection` a bare
  atom-keyed map rather than a reified `Projection.t()` unless this
  module's own `JsonDecoder` implementation calls `Projection
  .from_wire/1` on it, below.
  """

  use Commanded.ProcessManagers.ProcessManager,
    application: Catapult.Engine.Application,
    name: :delivery_feature_lifecycle,
    consistency: :strong

  require Logger

  alias Catapult.Config
  alias Catapult.Delivery.FeatureLifecycle.Projection
  alias Catapult.Delivery.FeatureLifecycle.Sequence
  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Dsl
  alias Catapult.Dsl.Workflow
  alias Catapult.Engine.Events.DraftCommitted
  alias Catapult.Engine.Events.FlowCompleted
  alias Catapult.Engine.Events.FlowOpened
  alias Catapult.Engine.Events.FlowResumed
  alias Catapult.Engine.Events.GateApproved
  alias Catapult.Engine.Events.GateDeclined
  alias Catapult.Engine.Events.RunFailed

  @enforce_keys [:project_id, :flow_id]
  @derive Jason.Encoder
  defstruct [:project_id, :flow_id, :entry_node_id, :flow_name, :projection]

  @type t :: %__MODULE__{
          project_id: binary(),
          flow_id: binary(),
          entry_node_id: binary() | nil,
          # The workflow-axis type name this flow's sequence is read
          # off (dsl-syntax.md §15.2) — `FlowOpened.flow_name` is the
          # convention-checked pairing point between the chain axis's
          # ticket face and the workflow axis's registry (§13's "no
          # cross-axis load-time check binds a queue's flow: value to
          # a chain bundle's flow: declaration of the same name" — an
          # unrecognized name simply resolves no positions, below).
          flow_name: String.t() | nil,
          # `nil` only transiently, between `struct(__MODULE__)`
          # (Commanded's own initial state) and this instance's first
          # `apply/2` clause, `%FlowOpened{}` by construction
          # (`interested?/1` only ever starts an instance on that
          # event) — set there. A plain `Projection.new()` default on
          # the field above would evaluate at *this module's* compile
          # time (`defstruct`'s own expansion bakes default values into
          # `__struct__/0`), which is exactly the compile-time
          # dependency `Catapult.Engine.Router`'s own moduledoc warns a
          # macro argument can create — checked here by running `mix
          # xref graph --label compile-connected --fail-above 0`
          # against the earlier, `Projection.new()`-defaulted version,
          # which failed it.
          projection: Projection.t() | nil
        }

  ## Routing

  def interested?(%FlowOpened{project_id: project_id, flow_id: flow_id}) do
    {:start, identity(project_id, flow_id)}
  end

  def interested?(%DraftCommitted{project_id: project_id}) do
    continue_current_flow(project_id)
  end

  def interested?(%RunFailed{project_id: project_id}) do
    continue_current_flow(project_id)
  end

  def interested?(%GateApproved{project_id: project_id, flow_id: flow_id}) do
    {:continue, identity(project_id, flow_id)}
  end

  def interested?(%GateDeclined{project_id: project_id, flow_id: flow_id}) do
    {:continue, identity(project_id, flow_id)}
  end

  def interested?(%FlowResumed{project_id: project_id, flow_id: flow_id}) do
    {:continue, identity(project_id, flow_id)}
  end

  def interested?(%FlowCompleted{project_id: project_id, flow_id: flow_id}) do
    {:stop, identity(project_id, flow_id)}
  end

  def interested?(_event), do: false

  defp continue_current_flow(project_id) do
    case DeliveryStore.current_open_flow_id(project_id) do
      nil -> false
      flow_id -> {:continue, identity(project_id, flow_id)}
    end
  end

  defp identity(project_id, flow_id), do: project_id <> ":" <> flow_id

  ## State

  def apply(%__MODULE__{} = pm, %FlowOpened{} = event) do
    %{
      pm
      | project_id: event.project_id,
        flow_id: event.flow_id,
        entry_node_id: event.entry_node_id,
        flow_name: event.flow_name,
        projection: Projection.new()
    }
    |> persist()
  end

  def apply(%__MODULE__{} = pm, %RunFailed{}) do
    case load_workflow() do
      {:ok, workflow} ->
        pm |> update_projection(&Projection.block(&1, workflow, pm.flow_name)) |> persist()

      {:error, _reason} ->
        pm
    end
  end

  # `GateApproved` advances the ticket to the next entry in its type's
  # own `statuses:` array after the gate's position — `Projection
  # .pass/2` marking the gate passed at the current commit signature is
  # the whole of it, since `resting/2`'s own ordinary walk already
  # finds the next non-passable position from there (`systems/delivery
  # .md`, ORC-34).
  def apply(%__MODULE__{} = pm, %GateApproved{gate: gate}) do
    pm |> update_projection(&Projection.pass(&1, {:gate, gate})) |> persist()
  end

  # `GateDeclined` moves the ticket straight to `throwback_to` — no
  # lookup against `passed` needed, the event already names the
  # resolved target (checked earlier-in-sequence at the command edge,
  # `Catapult.Dsl.Workflow.throwback_legal?/4`; dsl-syntax.md §15.10).
  def apply(%__MODULE__{} = pm, %GateDeclined{throwback_to: throwback_to}) do
    case load_workflow() do
      {:ok, workflow} ->
        position = Sequence.resolve_position(workflow, throwback_to)
        pm |> update_projection(&Projection.decline(&1, position)) |> persist()

      {:error, _reason} ->
        pm
    end
  end

  # `to_kind`/`to_gate` already name a resolved `Sequence.position()` —
  # the command edge that built `ResumeFlow` resolved it before
  # dispatch (`systems/engine.md`'s own entry) — so unlike `GateDeclined`
  # above, this needs no workflow load to fold, only the same
  # kind/gate-pair reconstruction `status/1` below already does for the
  # store's own flattened columns.
  def apply(%__MODULE__{} = pm, %FlowResumed{to_kind: to_kind, to_gate: to_gate}) do
    position = unflatten_position(to_kind, to_gate)
    pm |> update_projection(&Projection.resume(&1, position)) |> persist()
  end

  def apply(%__MODULE__{} = pm, %DraftCommitted{}, %{stream_version: sequence}) do
    pm
    |> update_projection(&Projection.commit(&1, sequence))
    |> persist()
  end

  defp update_projection(%__MODULE__{projection: nil} = pm, fun) do
    update_projection(%{pm | projection: Projection.new()}, fun)
  end

  defp update_projection(%__MODULE__{} = pm, fun), do: %{pm | projection: fun.(pm.projection)}

  defp load_workflow do
    case Dsl.load(Config.fetch!(:engine, :bundles_root)) do
      {:ok, %{workflow: %Workflow{} = workflow}} ->
        {:ok, workflow}

      {:ok, %{workflow: nil}} ->
        {:error, :no_workflow_bundle}

      {:error, reason} = error ->
        Logger.warning(
          "feature lifecycle skipped a projection update: bundle unloadable (#{inspect(reason)})",
          component: :delivery
        )

        error
    end
  end

  defp persist(%__MODULE__{project_id: project_id, flow_id: flow_id} = pm) do
    case load_workflow() do
      {:ok, workflow} ->
        resting = Projection.resting(workflow, pm.flow_name, pm.projection)
        warn_unplaceable(pm, workflow, resting)
        {status_kind, status_gate} = position_columns(resting)
        status_name = Sequence.name(workflow, pm.flow_name, resting)

        {blocked_origin_kind, blocked_origin_gate} =
          pm.projection |> Projection.blocked_origin() |> position_columns()

        DeliveryStore.upsert_feature_lifecycle(%{
          id: flow_id,
          project_id: project_id,
          entry_node_id: pm.entry_node_id,
          status_kind: status_kind,
          status_gate: status_gate,
          status_name: status_name,
          blocked_origin_kind: blocked_origin_kind,
          blocked_origin_gate: blocked_origin_gate,
          updated_sequence: pm.projection.commit_signature
        })

      {:error, _reason} ->
        :ok
    end

    pm
  end

  # An open work item the workflow axis cannot place is the accepted
  # cost of the two axes not being load-time bound (§15.7). Accepted is
  # not the same as invisible: it is logged once per projection write,
  # because the fix — a chain flow whose `ticket:` face uses a label
  # some declared type actually carries — is an authoring correction
  # nobody makes without being told.
  #
  # Narrowed at ORC-176: `resting` is only `nil` for a `pm.flow_name`
  # `Sequence.positions/2` truly has no sequence for — a declared-type
  # lookup that failed and isn't one of the closed inline-dispatch-point
  # kinds either (that module's own moduledoc). `setup`/`retro` resolve
  # there now, so this clause no longer fires for either, without a
  # `flow_name`-shaped exception carried here.
  defp warn_unplaceable(%__MODULE__{} = pm, %Workflow{types: types}, nil) do
    unless Map.has_key?(types, pm.flow_name) do
      Logger.warning(
        "flow #{pm.flow_id} opened as #{inspect(pm.flow_name)}, which names no declared " <>
          "work-item type in the loaded workflow bundle — it is projected without a position " <>
          "(dsl-syntax.md §15.7)",
        component: :delivery
      )
    end
  end

  defp warn_unplaceable(%__MODULE__{}, %Workflow{}, _placed), do: :ok

  defp position_columns(nil), do: {nil, nil}
  defp position_columns({:kind, kind}), do: {to_string(kind), nil}
  defp position_columns({:gate, name}), do: {nil, name}

  # The reverse of `position_columns/1`, for `FlowResumed`'s own
  # flattened `to_kind`/`to_gate` pair (`Catapult.Engine.Events
  # .FlowResumed`'s own moduledoc: never both set, never both nil).
  # `String.to_existing_atom/1`, never `to_atom/1`, the identical
  # discipline `Sequence.to_position/1` already takes — a `to_kind` on
  # this event only ever came from a `Sequence.position()`'s own
  # `{:kind, atom}` the command edge resolved from the closed
  # `Catapult.Dsl.SystemStatus` set, already in the atom table.
  defp unflatten_position(to_kind, nil) when not is_nil(to_kind),
    do: {:kind, String.to_existing_atom(to_kind)}

  defp unflatten_position(nil, to_gate) when not is_nil(to_gate), do: {:gate, to_gate}

  ## Nothing to dispatch in Phase 4 (`systems/delivery.md`): "what
  ## advancing past a gate on a human's word dispatches to stays open,
  ## unchanged by this ticket" — Commanded's own default `handle/2`
  ## (always `[]`) is exactly right here, so it is not overridden.

  @doc """
  The composite `Sequence.position/0` a flow's projected row currently
  carries — the work surface's own read (see
  `Catapult.Delivery.Store.get_feature_lifecycle/2`).

  `nil` when the row carries no position at all, which happens for
  exactly one reason and is worth naming: the flow's `flow_name` does
  not resolve to a declared type in the loaded workflow bundle. No
  load-time check binds the two axes (dsl-syntax.md §13, §15.7 — the
  same non-binding §11 holds everywhere else), so this is a defined
  outcome rather than a defect: the work item exists and is open, and
  the workflow axis simply has no sequence to place it in. §15.7 names
  it "the residual failure this leaves" and records it as the accepted
  cost of composability.
  """
  @spec status(Catapult.Delivery.Store.FeatureLifecycle.t()) :: Sequence.position() | nil
  def status(%Catapult.Delivery.Store.FeatureLifecycle{status_kind: kind})
      when not is_nil(kind) do
    {:kind, String.to_existing_atom(kind)}
  end

  def status(%Catapult.Delivery.Store.FeatureLifecycle{status_gate: gate})
      when not is_nil(gate) do
    {:gate, gate}
  end

  def status(%Catapult.Delivery.Store.FeatureLifecycle{}), do: nil
end

defimpl Commanded.Serialization.JsonDecoder, for: Catapult.Delivery.FeatureLifecycle do
  alias Catapult.Delivery.FeatureLifecycle
  alias Catapult.Delivery.FeatureLifecycle.Projection

  @doc "See `FeatureLifecycle`'s own moduledoc entry: reifies the bare atom-keyed map `JsonSerializer.deserialize/2`'s `struct/2` call leaves in `projection` back into a `Projection.t()`."
  def decode(%FeatureLifecycle{projection: projection} = pm)
      when is_map(projection) and not is_struct(projection) do
    %{pm | projection: Projection.from_wire(projection)}
  end

  def decode(%FeatureLifecycle{} = pm), do: pm
end
