defmodule Catapult.Delivery.HostPort.MarkerTest do
  @moduledoc """
  Render/parse round-trip and the "anything else is not a marker"
  boundary (`systems/delivery.md`'s ORC-31 marker entry).
  """

  use ExUnit.Case, async: true

  alias Catapult.Delivery.HostPort.Marker

  test "renders and parses a scope_violation marker round-trip" do
    payload = %{paths: ["lib/a.ex", "lib/b.ex"]}
    body = Marker.render(:scope_violation, payload)

    assert body =~ "Ready for rework"
    assert body =~ "lib/a.ex"
    assert {:ok, {:scope_violation, ^payload}} = Marker.parse(body)
  end

  test "a human-written comment is not a marker" do
    assert :not_a_marker = Marker.parse("looks good to me!")
  end

  test "an empty comment is not a marker" do
    assert :not_a_marker = Marker.parse("")
  end

  test "a marker-shaped header naming an unknown kind is not a marker" do
    assert :not_a_marker =
             Marker.parse(~s(<!-- catapult:marker kind=not_a_real_kind payload={} -->\nsome body))
  end

  test "a marker header with a malformed JSON payload is not a marker" do
    assert :not_a_marker =
             Marker.parse(~s(<!-- catapult:marker kind=scope_violation payload={not json} -->))
  end

  test "kinds/0 lists the closed enum" do
    assert Marker.kinds() == [:scope_violation]
  end
end
