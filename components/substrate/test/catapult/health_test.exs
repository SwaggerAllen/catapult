defmodule Catapult.HealthTest do
  use ExUnit.Case, async: true
  import Plug.Test

  defmodule Ready do
    use Catapult.Component, slug: :ready
  end

  defmodule NotReady do
    use Catapult.Component, slug: :not_ready
    def ready?, do: false
  end

  test "reports sha and per-component readiness" do
    opts = Catapult.Health.init(components: [Ready])
    conn = Catapult.Health.call(conn(:get, "/health"), opts)

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["ok"] == true
    assert body["components"] == %{"ready" => true}
    assert is_binary(body["sha"])
  end

  test "503 when any component is not ready" do
    opts = Catapult.Health.init(components: [Ready, NotReady])
    conn = Catapult.Health.call(conn(:get, "/health"), opts)

    assert conn.status == 503
    assert Jason.decode!(conn.resp_body)["ok"] == false
  end

  test "passes through non-health paths" do
    opts = Catapult.Health.init(components: [Ready])
    conn = Catapult.Health.call(conn(:get, "/other"), opts)
    refute conn.halted
  end
end
