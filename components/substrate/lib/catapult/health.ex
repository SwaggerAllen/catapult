defmodule Catapult.Health do
  @moduledoc """
  The health endpoint plug (conventions §10, v5 §2.13): git SHA plus
  per-component readiness from the composer. Deploy detection and ops
  read the same facts — one HTTP GET, provider-independent.

  Mount with the component list:
      plug Catapult.Health, components: [Catapult.Foundation, ...]
  The SHA comes from the GIT_SHA env var, stamped at build time.
  """

  @behaviour Plug
  import Plug.Conn

  alias Catapult.Component.Composer

  @impl Plug
  def init(opts), do: Keyword.fetch!(opts, :components)

  @impl Plug
  def call(%Plug.Conn{path_info: ["health"]} = conn, components) do
    readiness = Composer.readiness(components)
    ok? = Enum.all?(readiness, fn {_slug, ready} -> ready end)

    body =
      Jason.encode!(%{
        sha: Elixir.System.get_env("GIT_SHA", "dev"),
        ok: ok?,
        components: readiness
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(if(ok?, do: 200, else: 503), body)
    |> halt()
  end

  def call(conn, _components), do: conn
end
