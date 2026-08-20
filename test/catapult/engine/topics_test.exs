defmodule Catapult.Engine.TopicsTest do
  use ExUnit.Case, async: true

  alias Catapult.Engine.Topics

  test "ready_scopes/1 renders the engine's slug-spine topic name" do
    assert Topics.ready_scopes("proj-1") == "engine:ready_scopes:proj-1"
  end

  test "subscribe/1 then broadcast/2 delivers the message to the subscriber" do
    topic = Topics.ready_scopes("topics-test")
    :ok = Topics.subscribe(topic)

    assert :ok = Topics.broadcast(topic, :hello)
    assert_receive :hello
  end

  test "a broadcast on a different topic is not delivered" do
    :ok = Topics.subscribe(Topics.ready_scopes("topics-test-a"))
    assert :ok = Topics.broadcast(Topics.ready_scopes("topics-test-b"), :hello)
    refute_receive :hello
  end
end
