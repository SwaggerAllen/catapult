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

  alias Catapult.Engine.EventStore, as: CatapultEventStore

  @moduletag :capture_log

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
end
