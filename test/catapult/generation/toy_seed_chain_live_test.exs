defmodule Catapult.Generation.ToySeedChainLiveTest do
  @moduledoc """
  ORC-216: the boundary's live suite proves a dispatched run end to
  end against the reference instance — the toy seed
  (`Catapult.ToySeed`) through the test-project lifecycle and
  provisioning surface (`systems/delivery.md`'s ORC-216 entry), not
  through this process's own `HostPort.Actions` calls the way ORC-10's
  original version of this file did.

  **Why this file used to stop at "dispatch accepted," and why it no
  longer has to.** A dispatched GitHub Actions run calls back to
  whichever plane is reachable — the reference instance's own database
  (`SETUP.md` §2), never this job's own throwaway Postgres. A
  `dispatch_run` issued from *this* process used to write its
  correlation row into a database the deployed instance's callback
  could never see, so observing a round trip from here was theater.
  ORC-216 closes that gap: this test asks the *deployed* plane itself
  to provision a project (mint, bind to the one fixture repo this
  ticket's scope allows — `SwaggerAllen/catapult-test`, reset its
  fixture content, intake the raft) and to dispatch against it, then
  reads the outcome back from that same deployed plane over its own
  provisioning surface — never from this job's own database.

  **The no-polling rule's named exception is what makes closing the
  loop legal at all** (`systems/foundation.md`'s live suite,
  conventions §9): a live check may bound-poll a run it dispatched
  itself, because nothing else in this system observes that run's
  completion and the observer is the same process that started it.
  This is not the "wait out a rollout" case §9 refuses — a bounded
  overall deadline, an ordinary fixed poll interval, against the
  plane's own terminal-status read, scoped to the one project this
  test call itself provisioned.

  **What this proves for real**: the provisioning surface's bearer
  auth, minting and binding a project, resetting the bound repo's
  fixture content and intaking the raft, the deployed sweeper picking
  up a freshly bound project with no engine row of its own yet
  (`Catapult.Generation.Sweeper`'s own ORC-216 entry) and dispatching
  `feature_expansion` — the toy chain's one entry tier — onto a real
  GitHub Actions run, that run installing Claude Code and running the
  pinned runner harness for real, and the result-report landing back
  on the same database that issued the dispatch. The rest of the toy
  chain (every tier past `feature_expansion`) is not driven here — how
  far the sweeper is allowed to carry it before release is a cost
  question this ticket's design pass named rather than answered
  (`systems/delivery.md`'s ORC-216 entry), so this test releases its
  project the moment it observes `feature_expansion`'s own dispatched
  run reach a terminal status.

  **Needs setup this environment cannot supply.** `DELIVERY_PROVISIONING_TOKEN`
  defaults to a fake string (`config/test.exs`) unless the live-suite
  job's own environment overrides it with the same value the deployed
  plane's own `DELIVERY_PROVISIONING_TOKEN` holds — see this ticket's
  hand-back for what the operator still has to wire in.
  """

  use ExUnit.Case, async: true

  alias Catapult.Config.Secret
  alias Catapult.Delivery
  alias Catapult.ToySeed

  @moduletag :live

  # One bounded request per call, `Req`'s own defaults for the rest —
  # the same discipline `Catapult.HealthLiveTest` already keeps.
  @request_timeout :timer.seconds(30)

  # The no-polling rule's named exception (`systems/foundation.md`):
  # an ordinary fixed interval, a bounded overall deadline, against a
  # run this test call itself dispatched.
  @poll_interval :timer.seconds(5)
  @poll_deadline :timer.minutes(15)

  @entry_tier "feature_expansion"

  test "provisions a test project through the deployed plane and drives a dispatched run end to end" do
    base = Application.fetch_env!(:catapult, :live_base_url)
    headers = [{"authorization", "Bearer #{provisioning_token()}"}]

    provisioned =
      Req.post!(base <> "/dispatch/test-project",
        headers: headers,
        json: %{files: ToySeed.reset_files()},
        retry: false,
        receive_timeout: @request_timeout,
        connect_options: [timeout: @request_timeout]
      )

    # The body and headers are the only evidence a failed run leaves
    # here: a bare status assertion reported a 504 that the plane
    # itself never emits, and nothing in the log said where it came from.
    assert provisioned.status == 200,
           "provisioning answered #{provisioned.status}: body #{inspect(provisioned.body)}, " <>
             "headers #{inspect(provisioned.headers)}"

    assert %{"project_id" => project_id} = provisioned.body

    try do
      terminal = poll_terminal_status!(base, headers, project_id, @entry_tier)

      assert terminal["status"] == "completed",
             "expected feature_expansion's dispatched run to complete, got: #{inspect(terminal)}"

      assert terminal["outcome"] == "success",
             "expected a successful outcome, got: #{inspect(terminal)}"

      assert is_binary(terminal["credential_used"]) and terminal["credential_used"] != "",
             "expected a credential_used name, got: #{inspect(terminal)}"

      assert is_binary(terminal["body_sha"]) and terminal["body_sha"] != "",
             "expected the committed draft's body_sha, got: #{inspect(terminal)}"
    after
      release!(base, headers, project_id)
    end
  end

  defp poll_terminal_status!(base, headers, project_id, tier) do
    deadline = System.monotonic_time(:millisecond) + @poll_deadline
    poll_terminal_status!(base, headers, project_id, tier, deadline)
  end

  defp poll_terminal_status!(base, headers, project_id, tier, deadline) do
    case Req.get(base <> "/dispatch/test-project/#{project_id}/status/#{tier}",
           headers: headers,
           retry: false,
           receive_timeout: @request_timeout,
           connect_options: [timeout: @request_timeout]
         ) do
      {:ok, %{status: 200, body: %{"status" => status} = body}}
      when status in ["completed", "failed"] ->
        body

      _not_yet_terminal ->
        if System.monotonic_time(:millisecond) >= deadline do
          flunk("timed out waiting for #{tier}'s dispatched run to reach a terminal status")
        else
          Process.sleep(@poll_interval)
          poll_terminal_status!(base, headers, project_id, tier, deadline)
        end
    end
  end

  defp release!(base, headers, project_id) do
    Req.post!(base <> "/dispatch/test-project/#{project_id}/release",
      headers: headers,
      retry: false,
      receive_timeout: @request_timeout,
      connect_options: [timeout: @request_timeout]
    )

    :ok
  end

  defp provisioning_token, do: Secret.unwrap(Delivery.provisioning_token())
end
