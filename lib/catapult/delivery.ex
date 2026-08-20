defmodule Catapult.Delivery do
  @moduledoc """
  The protocol plane (`systems/delivery.md`): the host port's
  dispatch-facing slice pulled forward into Phase 3 with the
  generation executor (ORC-9) — context-fetch, result-report, OIDC
  validation, run correlation, and the Actions adapter + in-memory
  fake. The rest of the host port (feature-lifecycle PR management,
  decline harvesting) is Phase 4.
  """

  use Catapult.Component, slug: :delivery

  alias Catapult.Config.Secret
  alias Catapult.Delivery.Dispatch
  alias Catapult.Delivery.Store

  @impl Catapult.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-only"]

  @impl Catapult.Component
  def config do
    [
      # The operator's own GitHub credential (a fine-grained PAT or
      # GitHub App installation token) for calling the Actions API —
      # distinct from the customer-side model credentials named in v5
      # §7.12.1, which the plane never holds at all.
      {:github_token, "DELIVERY_GITHUB_TOKEN", cast: :string, secret: true},
      {:dispatch_workflow_file, "DELIVERY_DISPATCH_WORKFLOW_FILE",
       cast: :string, default: "catapult-dispatch.yml"},
      {:dispatch_ref, "DELIVERY_DISPATCH_REF", cast: :string, default: "main"},
      # Real-vs-fake adapter selection rides config like every other
      # external in this codebase (v5 §2.12), not a build-shape
      # constant: `Catapult.Delivery.HostPort.Actions` in dev/prod,
      # `.Fake` in test (`config/test.exs`).
      {:host_port_adapter, "DELIVERY_HOST_PORT_ADAPTER",
       cast: &__MODULE__.cast_adapter/1, default: "actions"},
      {:oidc_audience, "DELIVERY_OIDC_AUDIENCE", cast: :string, default: "catapult"},
      {:oidc_jwks_url, "DELIVERY_OIDC_JWKS_URL",
       cast: :string, default: "https://token.actions.githubusercontent.com/.well-known/jwks"},
      # `false` in test (`config/test.exs`): the strategy process still
      # starts and is structurally exercised, but never fetches over
      # the network — the default suite's chain never reaches it
      # anyway, since the fake host port bypasses HTTP/OIDC entirely
      # (conventions §9).
      {:oidc_jwks_autostart, "DELIVERY_OIDC_JWKS_AUTOSTART", cast: :boolean, default: "true"}
    ]
  end

  @doc "Casts the configured adapter name to its module."
  @spec cast_adapter(String.t()) :: {:ok, module()} | {:error, String.t()}
  def cast_adapter("actions"), do: {:ok, Catapult.Delivery.HostPort.Actions}
  def cast_adapter("fake"), do: {:ok, Catapult.Delivery.HostPort.Fake}
  def cast_adapter(other), do: {:error, "is #{inspect(other)}, expected \"actions\" or \"fake\""}

  @impl Catapult.Component
  def api_surface do
    [
      # Collision-checked and shaped like every other route this
      # platform will ever declare (`systems/foundation.md`'s design
      # note) — the general composed router waits for dashboard's
      # Phase 4/7 web layer, so what actually serves these paths today
      # is `Catapult.Foundation.DispatchPlug`'s hand-wired dispatch,
      # not this registry. `:partner` audience: reached by a runner
      # acting on the project's behalf, never end users.
      {{:fetch_context, 2}, :get, "/dispatch/context/:run_key",
       version: "v1", audience: :partner},
      {{:report_result, 2}, :post, "/dispatch/report/:run_key", version: "v1", audience: :partner}
    ]
  end

  @impl Catapult.Component
  def processes do
    [{:delivery_oidc_strategy, :singleton}]
  end

  @impl Catapult.Component
  def children do
    [{Catapult.Delivery.Oidc.Strategy, []}]
  end

  @doc "The configured host port adapter — `Catapult.Delivery.HostPort.Actions` or `.Fake`."
  @spec host_port_adapter() :: module()
  def host_port_adapter, do: Catapult.Config.fetch!(:delivery, :host_port_adapter)

  @doc "Unwrapped for the one call site that needs it (`Catapult.Delivery.HostPort.Actions`)."
  @spec github_token() :: Secret.t()
  def github_token, do: Catapult.Config.fetch!(:delivery, :github_token)

  @doc "A committed draft's raw body, cached for the review-tier `draft` variable (`Catapult.Delivery.Store.DraftBody`)."
  @spec get_draft_body(binary(), binary()) :: String.t() | nil
  def get_draft_body(project_id, node_id), do: Store.get_draft_body(project_id, node_id)

  @doc "Caches a committed draft's raw body — see `get_draft_body/2`."
  @spec put_draft_body(binary(), binary(), String.t(), String.t()) :: :ok
  def put_draft_body(project_id, node_id, body, body_sha),
    do: Store.put_draft_body(project_id, node_id, body, body_sha)

  @doc "Boundary export backing the `api_surface/0` declaration above — see `Catapult.Delivery.Dispatch.fetch_context/2`."
  @spec fetch_context(Plug.Conn.t(), binary()) :: Plug.Conn.t()
  defexport(fetch_context(conn, run_key), do: Dispatch.fetch_context(conn, run_key))

  @doc "Boundary export backing the `api_surface/0` declaration above — see `Catapult.Delivery.Dispatch.report_result/2`."
  @spec report_result(Plug.Conn.t(), binary()) :: Plug.Conn.t()
  defexport(report_result(conn, run_key), do: Dispatch.report_result(conn, run_key))
end
