defmodule Catapult.Generation.ToySeedChainLiveTest do
  @moduledoc """
  The `:live` half of ORC-10's boundary test: the same toy seed
  (`Catapult.ToySeed`) through `Catapult.Delivery.HostPort.Actions` —
  real GitHub calls, no fake — against the bound fixture repo
  (`SwaggerAllen/catapult-test`, `systems/delivery.md`'s ORC-10 entry:
  "starts empty and no role here has a route to author a workflow file
  in a different repository, so the plane writes it there instead").

  **Scope, and why it stops where it does** (`docs/non-goals.md`'s
  ORC-29 entries bind this file as much as the offline test):

    * **No polling or retry-until-observed.** Closing the loop —
      waiting for the dispatched GitHub Actions run to actually invoke
      the pinned runner harness and report a result back — needs a
      *reachable* plane for that runner to call back to, and the only
      one that exists is the reference instance's own database
      (`SETUP.md` §2), never this job's own throwaway Postgres
      (`docs/non-goals.md`'s "no argv-sniffing" entry: the live-suite
      job gets a real, empty database same as every other run). A
      `dispatch_run` issued from *this* process writes its correlation
      row into a database the deployed instance's callback can never
      see, so any observed round trip here would be theater, not
      proof. What this test proves instead — real, bounded, and
      genuinely unavailable any other way — is that the two outbound
      calls the plane itself makes (reset the bound repo's fixture
      content, trigger a real `workflow_dispatch`) succeed against
      GitHub for real. Closing the loop by hand is `docs/chain-runbook.md`'s
      job, deliberately: a human reads the dispatched run's own log.
    * **One bounded request per call, no retry** — the same discipline
      `Catapult.HealthLiveTest` already keeps; `Catapult.Delivery
      .HostPort.Actions` sets no explicit timeout of its own (ORC-9),
      so this test relies on `Req`'s own defaults rather than
      retrofitting one onto already-reviewed code outside this
      ticket's `Touches:` line.
    * **Needs setup this environment cannot supply.** `DELIVERY_GITHUB_TOKEN`
      defaults to a fake string (`config/test.exs`) unless the live-suite
      job's own environment overrides it with a real, `contents:
      read`+`write`-scoped credential for the bound repo — see this
      ticket's hand-back for exactly what the operator still has to
      wire in.
  """

  use Catapult.DataCase, async: true

  alias Catapult.Delivery.HostPort.Actions
  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Dsl
  alias Catapult.Engine.Store.Node
  alias Catapult.Generation.ContextAssembly
  alias Catapult.ToySeed

  @moduletag :live

  # ORC-10's design decision (systems/delivery.md): the fixture repo
  # this project's dispatch-facing host port is bound against for the
  # milestone boundary. One home, named here rather than duplicated —
  # a second live test binding a project needs the same two strings,
  # not a third fact to keep in sync.
  @repo_owner "SwaggerAllen"
  @repo_name "catapult-test"

  test "resetting the bound repo's fixture content succeeds for real" do
    project_id = "toy-seed-live-#{System.unique_integer([:positive])}"
    DeliveryStore.put_project_binding(project_id, @repo_owner, @repo_name)

    assert :ok = Actions.reset_repo(project_id, ToySeed.reset_files())
  end

  test "dispatching feature_expansion against the bound repo is accepted for real" do
    project_id = "toy-seed-live-#{System.unique_integer([:positive])}"
    DeliveryStore.put_project_binding(project_id, @repo_owner, @repo_name)

    {:ok, loaded} = Dsl.load(".")

    # The same bypass-readiness shape the offline test uses (see its
    # own moduledoc): `input.project_doc` never resolves today, so
    # `ReadyScopes` would never hand this scope to a dispatch worker —
    # proven directly rather than through the selection query that
    # can't select it yet.
    candidate = %Node{
      id: "virtual:feature_expansion:#{inspect(%{})}",
      project_id: project_id,
      tier: "feature_expansion",
      scope_key: %{},
      parent_node_id: nil,
      status: :absent
    }

    assert {:ok, request} =
             ContextAssembly.build(loaded.chain, project_id, "feature_expansion", candidate)

    assert {:ok, %{run_key: run_key}} = Actions.dispatch_run(request)
    assert DeliveryStore.get_dispatch_run(run_key).status == :dispatched
  end
end
