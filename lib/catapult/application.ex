defmodule Catapult.Application do
  @moduledoc """
  The composed root (conventions §4): children come from the component
  registries via the composer, never by hand. Boot validates the
  registry set and loads every declared configuration value before
  anything starts — a collision or a missing variable fails the boot,
  and CI's audit fails the build on the half it can see, whichever comes
  first (`Catapult.Boot`).
  """
  use Application

  alias Catapult.Boot
  alias Catapult.Component.Composer
  alias Catapult.Config

  @impl Application
  def start(_type, _args) do
    Boot.load!()
    children = Composer.children(Boot.components()) ++ health_children()
    Supervisor.start_link(children, strategy: :one_for_one, name: Catapult.Supervisor)
  end

  # `serve_health` selects what this *build* starts and stays in
  # `config/*.exs`; the port is what a deployment tunes and comes from
  # foundation's declaration (systems/foundation.md).
  defp health_children do
    if Application.get_env(:catapult, :serve_health, false) do
      port = Config.fetch!(:foundation, :health_port)
      [{Plug.Cowboy, scheme: :http, plug: Catapult.HealthEndpoint, options: [port: port]}]
    else
      []
    end
  end
end
