defmodule Catapult.Engine.Events.FlowOpenedV1Test do
  @moduledoc """
  The version-1 → version-2 upcast (v5 §2.4's upcasting discipline,
  `systems/engine.md`'s "replay fixtures retain every historical
  shape").
  """

  use ExUnit.Case, async: true

  alias Catapult.Engine.Events
  alias Catapult.Engine.Events.FlowOpened
  alias Catapult.Engine.Events.FlowOpenedV1
  alias Commanded.Event.Upcaster

  test "both versions are registered, and each resolves to its own module" do
    assert {:flow_opened, 1} in Events.registry()
    assert {:flow_opened, 2} in Events.registry()
    assert Events.module(:flow_opened, 1) == FlowOpenedV1
    assert Events.module(:flow_opened, 2) == FlowOpened
  end

  test "a v1 event upcasts to v2 with membership nil, never a guessed container" do
    # `nil` is the honest answer: a v1 event was written before
    # containers existed, so the work item it opened was genuinely a
    # member of nothing. A backfilled guess would have made an unowned
    # work item silently count into some queue's population.
    v1 = %FlowOpenedV1{
      project_id: "p1",
      flow_id: "f1",
      flow_name: "feature",
      entry_node_id: "n1",
      ticket_ref: "REF-1",
      actor_id: "a1"
    }

    assert %FlowOpened{} = upcast = Upcaster.upcast(v1, %{})

    assert upcast.project_id == "p1"
    assert upcast.flow_id == "f1"
    assert upcast.flow_name == "feature"
    assert upcast.entry_node_id == "n1"
    assert upcast.ticket_ref == "REF-1"
    assert upcast.actor_id == "a1"
    assert upcast.container_id == nil
    assert upcast.queue == nil
  end
end
