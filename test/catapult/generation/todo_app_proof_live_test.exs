defmodule Catapult.Generation.TodoAppProofLiveTest do
  @moduledoc """
  ORC-112, `docs/build-plan.md`'s Phase 5 exit criterion: starts the
  proof that a document graph scaffolded from a seed gets reviewed
  through the Phase 4 loop, against Waypoint (`Catapult.TodoAppSeed`),
  the small todo-app raft written for this exit run.

  **Why this is not tagged `:live`, unlike `ToySeedChainLiveTest`.**
  `mix test --only live` is the boundary suite's own cadence, and the
  boundary suite already runs a toy chain end to end every milestone
  through that same tag. `Catapult.Delivery.Provisioning.provision/1`
  releases whichever test project is currently `:active` the moment a
  *second* one is minted (`systems/delivery.md`'s ORC-216 entry: "at
  most one active, by construction of the mint operation") — so
  running this test under the same tag, in the same `mix test --only
  live` invocation, would race the boundary suite's own project for
  that one slot, and whichever provisions second would silently pull
  the rug out from under the other. `:live_todo_app_proof` is its own
  tag, excluded by default in `test/test_helper.exs` exactly like
  `:live` is, and re-included on its own: `mix test --only
  live_todo_app_proof`. This is the "dispatch input on
  `pipeline-live-suite.yml` selecting this proof rather than the
  boundary suite" `docs/build-plan.md`'s Phase 5 section names as
  author-owned and still to be wired — this test is the command that
  input has to run once it exists.

  **Why this test stops at provisioning, and touches neither polling
  nor release.** The proof's own middle is the author reviewing and
  declining through `document-review` across hours or days, which no
  bounded test spans (`docs/build-plan.md`'s own words) — unlike
  `ToySeedChainLiveTest`, which dispatches exactly one tier and can
  afford to poll a single run to a terminal status inside one test's
  deadline. This test's job ends at "the project is minted, bound, and
  the raft is intaking" — the deployed sweeper picks it up from there
  the same way it picks up any freshly bound project
  (`Catapult.Generation.Sweeper`'s ORC-216 entry), with no engine row
  of its own yet. Nothing here releases the project: doing so would
  undo the one thing this run is for. Release is the author's own
  action, once review is done, through the same provisioning surface
  `ToySeedChainLiveTest.release!/3` already demonstrates the shape of.

  **What this proves for real**: the provisioning surface's bearer
  auth, minting and binding a project to the one fixture repo this
  system allows (`SwaggerAllen/catapult-test`), resetting its content
  to Waypoint's raft, and intaking it — the same mechanism
  `ToySeedChainLiveTest` already exercises, pointed at a different
  raft and left running rather than polled to one tier's completion.

  **Needs setup this environment cannot supply.**
  `DELIVERY_PROVISIONING_TOKEN` defaults to a fake string
  (`config/test.exs`) unless the live-suite job's own environment
  overrides it with the same value the deployed plane holds — see
  `ToySeedChainLiveTest`'s own moduledoc and this ticket's hand-back
  for what the operator still has to wire in.
  """

  use ExUnit.Case, async: true

  alias Catapult.Config.Secret
  alias Catapult.Delivery
  alias Catapult.TodoAppSeed

  @moduletag :live_todo_app_proof

  # One bounded request per call, `Req`'s own defaults for the rest —
  # the same discipline `ToySeedChainLiveTest` already keeps.
  @request_timeout :timer.seconds(30)

  test "provisions Waypoint's raft through the deployed plane and leaves the project active for review" do
    base = Application.fetch_env!(:catapult, :live_base_url)
    headers = [{"authorization", "Bearer #{provisioning_token()}"}]

    provisioned =
      Req.post!(base <> "/dispatch/test-project",
        headers: headers,
        json: %{files: TodoAppSeed.reset_files()},
        retry: false,
        receive_timeout: @request_timeout,
        connect_options: [timeout: @request_timeout]
      )

    # Same reason as toy_seed_chain_live_test.exs: the body and headers
    # are the only evidence a failed run leaves here.
    assert provisioned.status == 200,
           "provisioning answered #{provisioned.status}: body #{inspect(provisioned.body)}, " <>
             "headers #{inspect(provisioned.headers)}"

    assert %{"project_id" => project_id, "ref" => ref} = provisioned.body
    assert is_binary(project_id) and project_id != ""
    assert is_binary(ref) and ref != ""

    # No release here, deliberately (this module's own moduledoc): the
    # project stays `:active` for the author to review through
    # `document-review` over the following hours or days.
    IO.puts(
      "Waypoint provisioned: project_id=#{project_id} ref=#{ref} — " <>
        "left active for review, release through the provisioning surface when done."
    )
  end

  defp provisioning_token, do: Secret.unwrap(Delivery.provisioning_token())
end
