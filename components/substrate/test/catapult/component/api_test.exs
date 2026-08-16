defmodule Catapult.Component.APITest do
  use ExUnit.Case, async: true

  defmodule Exporting do
    use Catapult.Component, slug: :exporting

    def errors, do: [{:exporting_missing, "no such thing", remedy: "check the id"}]

    defexport get_thing(id) do
      {:ok, id}
    end

    defexport put_thing(id, attrs) do
      {:ok, id, attrs}
    end

    defexport ping do
      :pong
    end

    defexport metadata do
      Logger.metadata()
    end

    defexport fail do
      {:error, __MODULE__.Error.new(:exporting_missing)}
    end

    defexport nest do
      {Logger.metadata(), metadata()}
    end

    def internal(x), do: x
  end

  defmodule Exporting.Error do
    @moduledoc false
    use Catapult.Error, component: Exporting
  end

  defmodule Nesting do
    use Catapult.Component, slug: :nesting

    defexport outer do
      {Logger.metadata(), Exporting.metadata(), Logger.metadata()}
    end
  end

  defmodule NoExports do
    use Catapult.Component, slug: :quiet
  end

  defp listen(events) do
    ref = make_ref()
    parent = self()
    name = "#{inspect(ref)}"

    :telemetry.attach_many(
      name,
      events,
      fn event, _measurements, meta, _ -> send(parent, {:telemetry, event, meta}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(name) end)
  end

  test "defexport wraps the function in a telemetry span on the slug spine" do
    listen([
      [:catapult, :exporting, :get_thing, :start],
      [:catapult, :exporting, :get_thing, :stop]
    ])

    assert {:ok, 42} = Exporting.get_thing(42)
    assert_received {:telemetry, [:catapult, :exporting, :get_thing, :start], _meta}
    assert_received {:telemetry, [:catapult, :exporting, :get_thing, :stop], _meta}
  end

  test "defexport leaves the export trace api_surface/0 validates against" do
    # In declaration order, and covering only what crossed the macro:
    # `internal/1` is a public function, not a boundary export.
    assert Exporting.__catapult_exports__() == [
             {:get_thing, 1},
             {:put_thing, 2},
             {:ping, 0},
             {:metadata, 0},
             {:fail, 0},
             {:nest, 0}
           ]
  end

  test "a component that exports nothing still answers the question" do
    assert NoExports.__catapult_exports__() == []
  end

  describe "the Logger metadata floor" do
    test "an export sets component and roots a trace" do
      inside = Exporting.metadata()

      assert inside[:component] == :exporting
      assert is_binary(inside[:trace_id])
    end

    test "the outer component is restored on the way out, the trace is not" do
      Logger.metadata(component: :caller, trace_id: "abc")

      assert Exporting.metadata()[:component] == :exporting
      assert Logger.metadata()[:component] == :caller
      assert Logger.metadata()[:trace_id] == "abc"
    end

    test "an export called from outside any other leaves no component behind" do
      Logger.reset_metadata()

      assert Exporting.metadata()[:component] == :exporting
      refute Keyword.has_key?(Logger.metadata(), :component)
    end

    test "a nested export never overwrites an inherited trace id" do
      Logger.reset_metadata()

      {outer, inner, after_inner} = Nesting.outer()

      assert outer[:component] == :nesting
      assert inner[:component] == :exporting
      # The seam tracing exists to cross: one trace, not two.
      assert inner[:trace_id] == outer[:trace_id]
      assert after_inner[:component] == :nesting
    end
  end

  describe "span metadata" do
    test "a registered error kind rides the stop event" do
      listen([[:catapult, :exporting, :fail, :stop]])

      assert {:error, %{kind: :exporting_missing}} = Exporting.fail()

      assert_received {:telemetry, [:catapult, :exporting, :fail, :stop],
                       %{error_kind: :exporting_missing}}
    end

    test "everything else emits nothing at all" do
      listen([[:catapult, :exporting, :get_thing, :stop]])

      Exporting.get_thing(:secret_looking_value)

      assert_received {:telemetry, [:catapult, :exporting, :get_thing, :stop], meta}
      refute Map.has_key?(meta, :error_kind)
      # Arguments and return bodies never enter the operational channel.
      refute Enum.any?(Map.values(meta), &(&1 == :secret_looking_value))
    end
  end
end
