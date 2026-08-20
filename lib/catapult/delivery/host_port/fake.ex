defmodule Catapult.Delivery.HostPort.Fake do
  @moduledoc """
  The in-process fake (conventions §9 — ships with the port, never
  disposable relative to `Actions`): opens a dispatch-run record like
  the real adapter, then synchronously drives
  `Catapult.Delivery.Dispatch.simulate_result/2` with a canned result
  — no HTTP, no OIDC round trip, the same commit path a real inbound
  call would reach (`systems/generation.md`'s own standing decision
  that the fake is scope, not scaffolding).

  The canned result comes from `Application.get_env(:catapult,
  :fake_dispatch_result)`, a 1-arity function `request -> result_map`
  a test sets before dispatching — the same seam
  `Catapult.Config.Static`'s seed map already is for the config
  source, applied to a port instead. There is no sane platform
  default (a canned body has to match the tier's own grammar), so an
  unconfigured call raises loudly rather than returning a
  quietly-wrong success.
  """

  require Logger

  @behaviour Catapult.Delivery.HostPort

  alias Catapult.Delivery.Dispatch
  alias Catapult.Delivery.Store

  @impl Catapult.Delivery.HostPort
  def dispatch_run(request) do
    run_key = Ecto.UUID.generate()

    Store.insert_dispatch_run(%{
      id: run_key,
      project_id: request.project_id,
      node_id: request.node_id,
      tier: request.tier,
      scope_key: request.scope_key,
      repo_owner: "fake",
      repo_name: "fake",
      root_tag: request.root_tag,
      rendered_prompt: request.rendered_prompt,
      credential_sent: request.credential_name
    })

    # Mirrors the Actions adapter's own contract: `{:ok, run_key}`
    # means dispatch was accepted, not that the (here, simulated) run
    # eventually succeeded — a real dispatch can't know that either.
    # A caller that cares inspects `Store.get_dispatch_run/1`.
    case Dispatch.simulate_result(run_key, canned_result_fun().(request)) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("fake host port's canned result was rejected: #{inspect(reason)}",
          component: :delivery
        )
    end

    {:ok, %{run_key: run_key}}
  end

  defp canned_result_fun do
    Application.get_env(:catapult, :fake_dispatch_result) ||
      raise """
      Catapult.Delivery.HostPort.Fake needs a canned result — set
      Application.put_env(:catapult, :fake_dispatch_result, fn request -> %{...} end)
      before dispatching (conventions §9's fake, driven by the caller's own fixture).
      """
  end
end
