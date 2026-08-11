defmodule Catapult.Application do
  @moduledoc """
  The composed root (conventions §4): children come from the component
  registries via the composer, never by hand. Boot validates the
  registry set — a collision fails the boot, and CI's audit fails the
  build, whichever comes first.
  """
  use Application

  alias Catapult.Component.Composer

  @components Application.compile_env(:catapult, :components, [Catapult.Foundation])

  @impl Application
  def start(_type, _args) do
    Composer.validate!(@components)
    children = Composer.children(@components) ++ health_children()
    Supervisor.start_link(children, strategy: :one_for_one, name: Catapult.Supervisor)
  end

  defp health_children do
    if Application.get_env(:catapult, :serve_health, false) do
      port = Application.get_env(:catapult, :health_port, 4000)
      [{Plug.Cowboy, scheme: :http, plug: Catapult.HealthEndpoint, options: [port: port]}]
    else
      []
    end
  end
end
