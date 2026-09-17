defmodule CatapultWeb.Router do
  @moduledoc """
  Dashboard's own router (`systems/dashboard.md`, `systems/foundation.md`'s
  design pass): an ordinary `Phoenix.Router` naming `event-log` and
  `explain-why` directly, since no other component needs to declare a
  LiveView route the way several declare an `api_surface/0` one — only
  the boundary-export half of the listener needed a generic,
  registry-driven shape (`Catapult.Foundation.DispatchPlug`).

  Every route is project-scoped (ORC-87, `systems/dashboard.md`'s
  standing decision): there is no cross-project or "all projects" view
  anywhere in this system, so `:project_id` is not optional on a single
  route.
  """
  use CatapultWeb, :router

  import PhoenixStorybook.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :assign_root_layout
    plug :protect_from_forgery

    # HSTS is set here rather than through the endpoint's `force_ssl:`
    # (ORC-131), and the distinction is the deployment's: Render
    # terminates TLS and redirects HTTP to HTTPS at its edge, so a
    # public request never reaches this app over http and `Plug.SSL`'s
    # redirect could never fire on one. The one path that does not come
    # through the edge is the platform's health probe, which hits the
    # container's port directly — an endpoint-wide `force_ssl` would
    # answer that 301 and fail the deploy. That second half is why this
    # is permanent rather than vendor-specific, and why it survived the
    # move off App Platform unchanged: a probe reaching the container
    # directly is how a container health check works anywhere. So the redirect half buys nothing and risks the
    # rollout; HSTS, the half the edge does not supply, is real and
    # belongs on the browser surface alone. `/health` and `/dispatch/*`
    # are served by `Catapult.Foundation.DispatchPlug` ahead of this
    # router and never reach this pipeline, which is what makes putting
    # it here safe rather than merely narrower.
    #
    # This is also why `mix sobelow`'s `Config.HTTPS` stays ignored on
    # the gate line: it reads the endpoint's config for `force_ssl` and
    # cannot see a header set in a router pipeline. The ignore's own
    # comment carries that reason.
    plug :put_secure_browser_headers, %{
      "content-security-policy" => "default-src 'self'",
      "strict-transport-security" => "max-age=31536000"
    }
  end

  # A plain function body, not a literal `{Module, :root}` opt on
  # `plug :put_root_layout` directly — the latter is a compile edge to
  # `CatapultWeb.Layouts` (measured, `CatapultWeb.Endpoint`'s own
  # comment has the full reasoning).
  defp assign_root_layout(conn, _opts) do
    put_root_layout(conn, html: {CatapultWeb.Layouts, :root})
  end

  scope "/", CatapultWeb do
    pipe_through(:browser)

    live "/projects/:project_id/event-log", EventLogLive, :index
    live "/projects/:project_id/explain-why/:node_id", ExplainWhyLive, :show

    # `my-queue` is the one cross-project route in this system, on its
    # own stated reason (`systems/dashboard.md`'s ORC-75 narrowing of
    # ORC-87's "every route carries a project id"): it is not a route
    # missing a project id, it is one project-scoped read per project
    # the actor has standing in, merged for display.
    live "/my-queue", MyQueueLive, :index
    live "/projects/:project_id/board", BoardLive, :index
    live "/projects/:project_id/tickets/:flow_id", TicketLive, :show
    live "/projects/:project_id/tickets/:flow_id/review", DocumentReviewLive, :show
  end

  # `phoenix_storybook` ships no static export, so it is served live, at
  # a route, like the rest of this router. That was a constraint to work
  # around while design review read a static export published per
  # branch; it is now simply how the preview works — Render runs the
  # whole app per pull request and design review reads the storybook
  # from this route (`systems/dashboard.reasons.md` #24).
  scope "/" do
    storybook_assets()
  end

  scope "/" do
    pipe_through(:browser)
    live_storybook("/storybook", backend_module: CatapultWeb.Storybook)
  end
end
