defmodule Catapult.Component.APITest do
  use ExUnit.Case, async: true

  defmodule Exporting do
    use Catapult.Component, slug: :exporting

    defexport get_thing(id) do
      {:ok, id}
    end
  end

  test "defexport wraps the function in a telemetry span on the slug spine" do
    ref = make_ref()
    parent = self()

    :telemetry.attach_many(
      "#{inspect(ref)}",
      [[:catapult, :exporting, :get_thing, :start], [:catapult, :exporting, :get_thing, :stop]],
      fn event, _measurements, _meta, _ -> send(parent, {:telemetry, event}) end,
      nil
    )

    assert {:ok, 42} = Exporting.get_thing(42)
    assert_received {:telemetry, [:catapult, :exporting, :get_thing, :start]}
    assert_received {:telemetry, [:catapult, :exporting, :get_thing, :stop]}
  after
    :telemetry.detach("#{inspect(make_ref())}")
  end
end
