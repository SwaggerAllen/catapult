defmodule Catapult.Component.APITest do
  use ExUnit.Case, async: true

  defmodule Exporting do
    use Catapult.Component, slug: :exporting

    defexport get_thing(id) do
      {:ok, id}
    end

    defexport put_thing(id, attrs) do
      {:ok, id, attrs}
    end

    defexport ping do
      :pong
    end

    def internal(x), do: x
  end

  defmodule NoExports do
    use Catapult.Component, slug: :quiet
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

  test "defexport leaves the export trace api_surface/0 validates against" do
    # In declaration order, and covering only what crossed the macro:
    # `internal/1` is a public function, not a boundary export.
    assert Exporting.__catapult_exports__() == [
             {:get_thing, 1},
             {:put_thing, 2},
             {:ping, 0}
           ]
  end

  test "a component that exports nothing still answers the question" do
    assert NoExports.__catapult_exports__() == []
  end
end
