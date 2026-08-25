defmodule Catapult.Application do
  @moduledoc """
  The composed root (conventions §4): children come from the component
  registries via the composer, never by hand. Boot validates the
  registry set and loads every declared configuration value before
  anything starts — a collision or a missing variable fails the boot,
  and CI's audit fails the build on the half it can see, whichever comes
  first (`Catapult.Boot`).

  The one listener this instance serves publicly is `CatapultWeb.Endpoint`
  (ORC-35's dev pass, replacing the raw `Plug.Cowboy` mount ORC-9 built):
  `Catapult.Foundation.DispatchPlug` first in its pipeline, handling
  `/health` and every `api_surface/0`-declared route and passing
  anything else through; `CatapultWeb.Router` behind it, owning
  dashboard's own screens, the storybook, and the terminal 404.
  `SETUP.md` §2 and the README's "`/health` is the only served path"
  both changed the day ORC-9 added `/dispatch/*`, and change again here.
  """
  use Application

  alias Catapult.Boot
  alias Catapult.Component.Composer
  alias Catapult.Config
  alias Catapult.Config.Secret

  @impl Application
  def start(_type, _args) do
    Boot.load!()

    children =
      Composer.children(Boot.components()) ++
        [{Phoenix.PubSub, name: CatapultWeb.PubSub}, endpoint_child()]

    Supervisor.start_link(children, strategy: :one_for_one, name: Catapult.Supervisor)
  end

  # `CatapultWeb.Endpoint` is always part of the supervision tree —
  # `Phoenix.LiveViewTest`/`Phoenix.ConnTest` need the endpoint process
  # (PubSub included) running even where nothing binds a socket.
  # `serve_health` keeps its existing job: it is what this *build*
  # starts an actual listener for (`config/*.exs`), now read as the
  # endpoint's own `server:` override rather than gating whether the
  # child exists at all. The port is what a deployment tunes and comes
  # from foundation's declaration (systems/foundation.md), same as
  # before ORC-35.
  defp endpoint_child do
    {CatapultWeb.Endpoint,
     server: Application.get_env(:catapult, :serve_health, false),
     secret_key_base: Secret.unwrap(Config.fetch!(:foundation, :endpoint_secret_key_base)),
     http: [port: Config.fetch!(:foundation, :health_port)]}
  end
end
