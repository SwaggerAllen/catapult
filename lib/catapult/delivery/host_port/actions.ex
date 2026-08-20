defmodule Catapult.Delivery.HostPort.Actions do
  @moduledoc """
  The default execution substrate (`systems/generation.md`, v5
  §7.12.1): triggers a `workflow_dispatch` on the project's bound
  GitHub repo. Nothing outside this module may assume Actions — the
  contract is `Catapult.Delivery.HostPort`'s callback, not this
  adapter's own shape.

  **No failover, deliberately** (ORC-9's design rework): the shipped
  runner harness fails over on any non-zero exit and cannot yet be
  told "limit-class only" (no structured signal from the CLI's JSON
  mode is wired up there yet). Sending the credential pair here would
  let that blind failover fire on an ordinary bug, paying for the same
  failure twice. So this adapter sends the bindings `tunable`'s
  first-ordered credential alone — the second slot is never a dispatch
  input, so there is nothing for the harness's own failover to reach
  for even though it would try. The day the harness exposes a
  structured limit-class signal, this sends the full ordered pair
  instead of its head — a one-line change, not a new decision, because
  the contract was already built for two.

  The dispatch input is the plane-minted `run_key` and the chosen
  credential's *name* only — never a value. Model credentials are
  customer-side secrets the plane never holds (v5 §7.12.1); resolving
  `credential_name` to an actual key is the target repo's own workflow
  file's job, reading its own GitHub Actions secret.
  """

  @behaviour Catapult.Delivery.HostPort

  alias Catapult.Config
  alias Catapult.Config.Secret
  alias Catapult.Delivery.Store

  @impl Catapult.Delivery.HostPort
  def dispatch_run(request) do
    with {:ok, binding} <- fetch_binding(request.project_id),
         run_key = Ecto.UUID.generate(),
         {:ok, _resp} <- trigger_workflow(binding, run_key, request.credential_name) do
      Store.insert_dispatch_run(%{
        id: run_key,
        project_id: request.project_id,
        node_id: request.node_id,
        tier: request.tier,
        scope_key: request.scope_key,
        repo_owner: binding.repo_owner,
        repo_name: binding.repo_name,
        root_tag: request.root_tag,
        rendered_prompt: request.rendered_prompt,
        credential_sent: request.credential_name
      })

      {:ok, %{run_key: run_key}}
    end
  end

  defp fetch_binding(project_id) do
    case Store.get_project_binding(project_id) do
      nil -> {:error, {:no_project_binding, project_id}}
      binding -> {:ok, binding}
    end
  end

  defp trigger_workflow(binding, run_key, credential_name) do
    workflow_file = Config.fetch!(:delivery, :dispatch_workflow_file)
    ref = Config.fetch!(:delivery, :dispatch_ref)

    url =
      "https://api.github.com/repos/#{binding.repo_owner}/#{binding.repo_name}" <>
        "/actions/workflows/#{workflow_file}/dispatches"

    response =
      Req.post(url,
        auth: {:bearer, Secret.unwrap(Config.fetch!(:delivery, :github_token))},
        headers: [{"accept", "application/vnd.github+json"}],
        json: %{ref: ref, inputs: %{run_key: run_key, credential_name: credential_name}}
      )

    case response do
      {:ok, %{status: status} = resp} when status in 200..299 -> {:ok, resp}
      {:ok, resp} -> {:error, {:dispatch_failed, resp.status, resp.body}}
      {:error, reason} -> {:error, {:dispatch_failed, reason}}
    end
  end
end
