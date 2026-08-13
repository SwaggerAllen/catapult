defmodule Catapult.HealthEndpoint do
  @moduledoc """
  The served health surface (conventions §10): the substrate's health
  plug over the configured component set, 404 otherwise. Deploy
  detection and ops read this endpoint; nothing else is served here.
  """
  @behaviour Plug

  @impl Plug
  def init(_opts) do
    components = Application.get_env(:catapult, :components, [Catapult.Foundation])
    Catapult.Health.init(components: components)
  end

  @impl Plug
  def call(conn, health_opts) do
    conn = Catapult.Health.call(conn, health_opts)

    if conn.halted do
      conn
    else
      Plug.Conn.send_resp(conn, 404, "not found")
    end
  end
end
