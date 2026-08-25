defmodule CatapultWeb do
  @moduledoc """
  The web layer's own boundary and use-macros (`systems/dashboard.md`,
  ORC-35's dev pass — the first ticket to land `lib/catapult_web/**`).

  Carved out of the coarse `Catapult` boundary rather than folded into
  it: `Catapult.*` stays the plane's own reasoning (engine, dsl,
  generation, delivery), and this namespace is the only one that needs
  the router/LiveView macro surface. LiveViews and the router reach
  reads through `Catapult`'s own modules directly (this codebase's
  existing precedent — `Catapult.Engine.Store`,
  `Catapult.Engine.Projections.*` and `Catapult.Dsl` are called
  directly by `lib/catapult/generation/**` and `lib/catapult/delivery/**`
  today, no boundary-export indirection for reads); nothing under
  `Catapult.*` reaches back into this one.
  """
  use Boundary,
    deps: [
      Catapult,
      Phoenix,
      Phoenix.PubSub,
      Phoenix.LiveView,
      Phoenix.LiveView.Engine,
      Phoenix.LiveView.HTMLEngine,
      Phoenix.LiveView.Rendered,
      Phoenix.LiveView.TagEngine,
      Phoenix.Component,
      Phoenix.Component.Declarative,
      Plug,
      PhoenixStorybook,
      Commanded.EventStore,
      Commanded.EventStore.RecordedEvent,
      # `CatapultWeb.ConnCase`'s own sandbox setup (`test/support/`,
      # `Catapult.DataCase`'s same pattern).
      Ecto.Adapters.SQL.Sandbox
    ]

  @doc "The router macros: `use CatapultWeb, :router`."
  def router do
    quote do
      use Phoenix.Router

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  @doc "Presentational-layer helpers shared by every LiveView: `use CatapultWeb, :live_view`."
  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  @doc "Function-component helpers: `use CatapultWeb, :html`."
  def html do
    quote do
      use Phoenix.Component

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.Component
    end
  end

  @doc false
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
