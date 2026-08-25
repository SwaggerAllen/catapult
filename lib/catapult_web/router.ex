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
    plug :put_secure_browser_headers
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
  end

  # `phoenix_storybook` ships no static export (`bin/preview-build.sh`'s
  # own comment) — served live, at a route, like the rest of this
  # router. Mounting it is what flips that script's fallback message
  # from "no lib/catapult_web yet" to "the boot-and-snapshot step is
  # not written yet", which is this ticket's own scope boundary: the
  # export step stays unwritten, named for whoever picks it up next.
  scope "/" do
    storybook_assets()
  end

  scope "/" do
    pipe_through(:browser)
    live_storybook("/storybook", backend_module: CatapultWeb.Storybook)
  end
end
