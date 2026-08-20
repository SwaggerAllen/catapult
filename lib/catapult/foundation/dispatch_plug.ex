defmodule Catapult.Foundation.DispatchPlug do
  @moduledoc """
  The one plug this instance's single public listener mounts (ORC-9,
  `systems/foundation.md`'s design note): plain runtime `path_info`
  dispatch, not a router — no macro or behaviour coupling, so the
  compile-connected cap (`--fail-above 0`, this doc's own gate) stays
  untouched. `/health` keeps `Catapult.HealthEndpoint`'s own
  404-everything-else behavior on its own path; `/dispatch/*` forwards
  to delivery's boundary export (`Catapult.Delivery.fetch_context/2`,
  `.report_result/2` — the host port's dispatch-facing slice,
  `systems/generation.md`, `systems/delivery.md`); anything else is a
  404 this plug answers itself.

  Composed in `Catapult.Application` in place of mounting
  `Catapult.HealthEndpoint` directly. When dashboard's router lands
  and absorbs `api_surface/0` generically (Phase 4/7), this module's
  hand-wiring is what gets deleted, not the `api_surface/0`
  declarations underneath it.
  """
  @behaviour Plug

  alias Catapult.Delivery
  alias Catapult.HealthEndpoint

  @impl Plug
  def init(opts), do: HealthEndpoint.init(opts)

  @impl Plug
  def call(%Plug.Conn{path_info: ["health" | _]} = conn, health_opts) do
    HealthEndpoint.call(conn, health_opts)
  end

  def call(%Plug.Conn{path_info: ["dispatch", "context", run_key]} = conn, _health_opts) do
    Delivery.fetch_context(conn, run_key)
  end

  def call(%Plug.Conn{path_info: ["dispatch", "report", run_key]} = conn, _health_opts) do
    Delivery.report_result(conn, run_key)
  end

  def call(conn, _health_opts) do
    Plug.Conn.send_resp(conn, 404, "not found")
  end
end
