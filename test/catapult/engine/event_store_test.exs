defmodule Catapult.Engine.EventStoreTest do
  @moduledoc """
  The one test exercising the real, Postgres-backed adapter (v5 §2.4)
  end to end — proving the `AddEventStore` migration and
  `Catapult.Engine.EventStore`'s connection wiring genuinely work,
  which the rest of the suite (run against
  `Commanded.EventStore.Adapters.InMemory`, `config/test.exs`) never
  touches. Not `:live` (ORC-29): this reaches the same local Postgres
  the sandbox already uses, never a real external system.
  """

  use ExUnit.Case, async: false

  alias Catapult.Engine.Events.ActiveBundleFlipped
  alias Catapult.Engine.Events.DraftCommitted
  alias Catapult.Engine.Events.FindingAdjudicated
  alias Catapult.Engine.Events.ReviewWritten
  alias Catapult.Engine.EventStore, as: CatapultEventStore

  @moduletag :capture_log

  @committed_at ~U[2026-01-01 00:00:00Z]

  setup do
    {:ok, _pid} = start_supervised({CatapultEventStore, name: __MODULE__})
    :ok
  end

  test "appends to and reads back from the real event store schema" do
    stream_uuid = Ecto.UUID.generate()

    event = %EventStore.EventData{
      event_type: "Elixir.Catapult.Engine.Events.FlowCompleted",
      data: %Catapult.Engine.Events.FlowCompleted{project_id: "p1", flow_id: "f1"},
      metadata: %{}
    }

    assert :ok = CatapultEventStore.append_to_stream(stream_uuid, 0, [event], name: __MODULE__)

    assert {:ok,
            [
              %EventStore.RecordedEvent{
                data: %Catapult.Engine.Events.FlowCompleted{flow_id: "f1"}
              }
            ]} =
             CatapultEventStore.read_stream_forward(stream_uuid, 0, 1_000, name: __MODULE__)
  end

  # The round trip above proves the migration and the adapter wiring —
  # a different, still-needed fact from the ones below, which prove
  # `Catapult.Engine.Events.WireDecoding`'s repair against the real
  # serializer (`systems/engine.md`'s ORC-226 design pass). Every case
  # here is invisible to the default suite: `config/test.exs`'s
  # `Commanded.EventStore.Adapters.InMemory` performs no serialization
  # at all.

  test "ReviewWritten.kind survives the wire as an atom, not the string Jason would leave it as" do
    stream_uuid = Ecto.UUID.generate()

    event = %EventStore.EventData{
      event_type: "Elixir.Catapult.Engine.Events.ReviewWritten",
      data: %ReviewWritten{
        project_id: "p1",
        draft_id: "d1",
        review_id: "r1",
        score: 91,
        kind: :human
      },
      metadata: %{}
    }

    assert :ok = CatapultEventStore.append_to_stream(stream_uuid, 0, [event], name: __MODULE__)

    assert {:ok, [%EventStore.RecordedEvent{data: %ReviewWritten{kind: :human}}]} =
             CatapultEventStore.read_stream_forward(stream_uuid, 0, 1_000, name: __MODULE__)
  end

  test "ActiveBundleFlipped.axis survives the wire as an atom" do
    stream_uuid = Ecto.UUID.generate()

    event = %EventStore.EventData{
      event_type: "Elixir.Catapult.Engine.Events.ActiveBundleFlipped",
      data: %ActiveBundleFlipped{
        project_id: "p1",
        axis: :workflow,
        bundle_name: "default-flow",
        version: "1",
        flip_id: "flip-1"
      },
      metadata: %{}
    }

    assert :ok = CatapultEventStore.append_to_stream(stream_uuid, 0, [event], name: __MODULE__)

    assert {:ok, [%EventStore.RecordedEvent{data: %ActiveBundleFlipped{axis: :workflow}}]} =
             CatapultEventStore.read_stream_forward(stream_uuid, 0, 1_000, name: __MODULE__)
  end

  test "FindingAdjudicated.disposition survives the wire as an atom" do
    stream_uuid = Ecto.UUID.generate()

    event = %EventStore.EventData{
      event_type: "Elixir.Catapult.Engine.Events.FindingAdjudicated",
      data: %FindingAdjudicated{
        project_id: "p1",
        container_id: "c1",
        finding_id: "f1",
        disposition: :declined,
        reason: "not applicable"
      },
      metadata: %{}
    }

    assert :ok = CatapultEventStore.append_to_stream(stream_uuid, 0, [event], name: __MODULE__)

    assert {:ok, [%EventStore.RecordedEvent{data: %FindingAdjudicated{disposition: :declined}}]} =
             CatapultEventStore.read_stream_forward(stream_uuid, 0, 1_000, name: __MODULE__)
  end

  test "DraftCommitted's mint status/edge_type and edge type survive the wire as atoms" do
    stream_uuid = Ecto.UUID.generate()

    event = %EventStore.EventData{
      event_type: "Elixir.Catapult.Engine.Events.DraftCommitted",
      data: %DraftCommitted{
        project_id: "p1",
        node_id: "sysarch",
        tier: "sysarch",
        scope_key: %{},
        draft_id: "draft-1",
        body_sha: "sha-1",
        committed_at: @committed_at,
        mints: [
          %{
            node_id: "comp1",
            tier: "comp",
            scope_key: %{"name" => "comp1"},
            edge_name: "decomposition",
            edge_type: :fanout,
            status: :approved
          }
        ],
        edges: [
          %{edge_name: "ref1", type: :reference, target_node_id: "comp2"}
        ]
      },
      metadata: %{}
    }

    assert :ok = CatapultEventStore.append_to_stream(stream_uuid, 0, [event], name: __MODULE__)

    assert {:ok,
            [
              %EventStore.RecordedEvent{
                data: %DraftCommitted{
                  mints: [%{status: :approved, edge_type: :fanout}],
                  edges: [%{type: :reference}]
                }
              }
            ]} = CatapultEventStore.read_stream_forward(stream_uuid, 0, 1_000, name: __MODULE__)
  end

  test "an unrecognised value passes through decode/1 as the wire string, unchanged" do
    stream_uuid = Ecto.UUID.generate()

    event = %EventStore.EventData{
      event_type: "Elixir.Catapult.Engine.Events.ReviewWritten",
      data: %ReviewWritten{
        project_id: "p1",
        draft_id: "d1",
        review_id: "r1",
        score: 91,
        kind: :bogus
      },
      metadata: %{}
    }

    assert :ok = CatapultEventStore.append_to_stream(stream_uuid, 0, [event], name: __MODULE__)

    assert {:ok, [%EventStore.RecordedEvent{data: %ReviewWritten{kind: "bogus"}}]} =
             CatapultEventStore.read_stream_forward(stream_uuid, 0, 1_000, name: __MODULE__)
  end
end
