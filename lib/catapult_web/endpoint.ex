defmodule CatapultWeb.Endpoint do
  @moduledoc """
  The instance's one public listener (`SETUP.md` §2 — "the instance
  exposes one public port"). Two mechanisms share it, composed as
  plugs rather than as one router (`systems/foundation.md`'s design
  pass): `Catapult.Foundation.DispatchPlug` first, handling `/health`
  and every `api_surface/0`-declared route through its registry-driven
  dispatch and passing anything else through unhalted; then
  `CatapultWeb.Router`, which owns dashboard's own screens, the
  storybook, and the terminal 404 for a path neither mechanism claims.
  """
  use Phoenix.Endpoint, otp_app: :catapult

  alias Catapult.Foundation.DispatchPlug

  # No end-user session state in v0 (no login, no writes — "the
  # dashboard can never be a second write path"). Still required
  # infrastructure: `live/2`'s dead render wants a session to hang the
  # CSRF token on, the same as any Phoenix app's `:browser` pipeline.
  @session_options [
    store: :cookie,
    key: "_catapult_key",
    signing_salt: "catapult-dashboard",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  # `priv/static/assets/app.css` (`mix assets.build`/`assets.deploy`,
  # `systems/dashboard.md`'s ORC-183 entry) is what makes every daisyUI
  # class this system's screens use actually render — absent this plug,
  # the live route served no static asset of any kind. `only: ~w(assets)`
  # rather than the wider Phoenix default set: nothing else lives under
  # `priv/static` yet.
  plug Plug.Static, at: "/", from: :catapult, only: ~w(assets)

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart],
    pass: ["*/*"]

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  # Function plugs (`plug :name`), not module plugs (`plug Module`):
  # the latter's sugar calls `Module.init/1` at compile time, embedding
  # a literal reference that trips `mix xref`'s `compile-connected`
  # label (measured — the module-plug form put this file at 3 compile
  # edges against the `--fail-above 0` gate). An ordinary remote call
  # inside a function body is a runtime edge, the same shape `live/2`
  # already holds `--fail-above 0` at (`systems/foundation.md`'s own
  # probe) and the same reasoning `Catapult.Foundation.DispatchPlug`'s
  # own `apply/3` dispatch rests on.
  plug :dispatch_plug
  plug :dispatch_router

  defp dispatch_plug(conn, _opts) do
    DispatchPlug.call(conn, DispatchPlug.init([]))
  end

  defp dispatch_router(conn, _opts) do
    CatapultWeb.Router.call(conn, CatapultWeb.Router.init([]))
  end
end
