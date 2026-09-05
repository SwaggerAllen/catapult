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
  on the same database that issued the dispatch.

  **How far the toy chain runs before release, and why every run gets
  asserted rather than one** (ORC-216 named this cost question and
  left it open; ORC-225 answers it — `systems/delivery.md`'s own
  entry). This test no longer stops at `feature_expansion`'s own
  terminal status: it polls `Provisioning.runs/2`
  (`/dispatch/test-project/:project_id/runs`) until the whole run set
  reaches *quiescence* — every run terminal, and the same run-id set
  observed across two polls separated by more than one full
  `GENERATION_SWEEP_INTERVAL_MS` tick plus this test's own
  `@poll_interval` margin — then asserts every run individually,
  rather than the one tier `@entry_tier` alone named before. Live-suite
  run 26 is why: it read green with four of its five dispatched runs
  red, because nothing polled the other four. No new dispatch
  mechanism is added for this — `Catapult.Generation.Sweeper` runs
  exactly as it does today; this test only widens what it *asserts on*.

  **Needs setup this environment cannot supply.** `DELIVERY_PROVISIONING_TOKEN`
  defaults to a fake string (`config/test.exs`) unless the live-suite
  job's own environment overrides it with the same value the deployed
  plane's own `DELIVERY_PROVISIONING_TOKEN` holds — see this ticket's
  hand-back for what the operator still has to wire in.
  """

  use ExUnit.Case, async: true

  alias Catapult.Config.Secret
  alias Catapult.Delivery
  alias Catapult.Generation.Quiescence
  alias Catapult.ToySeed

  @moduletag :live

  # One bounded request per call, `Req`'s own defaults for the rest —
  # the same discipline `Catapult.HealthLiveTest` already keeps.
  @request_timeout :timer.seconds(30)

  # The no-polling rule's named exception (`systems/foundation.md`):
  # an ordinary fixed interval, a bounded overall deadline, against a
  # run this test call itself dispatched. Sized for a stub-mode
  # dispatch (ORC-223, `systems/generation.md`'s ORC-223 entry): under
  # the stub default this project provisions with, a dispatched run
  # skips "Install Claude Code" and "Run the agent" and reaches
  # terminal in however long a GitHub-hosted runner takes to queue,
  # start and run a checkout plus a report call — tens of seconds, not
  # minutes, for one dispatch.
  @poll_interval :timer.seconds(5)

  # ORC-225 widens what this deadline has to cover, from one dispatch
  # reaching terminal to the whole run set reaching quiescence
  # (`systems/generation.md`'s own entry) — up to two sequential
  # rounds on a toy-seed project today (a tick-0 draft round and the
  # review round it unblocks), each bounded by one dispatch's own
  # runner latency plus up to one sweep tick, plus this test's own
  # `@quiescence_window` tail charged once per round.
  @poll_deadline :timer.minutes(6)

  @entry_tier "feature_expansion"

  # `GENERATION_SWEEP_INTERVAL_MS`'s own default
  # (`lib/catapult/generation.ex`) plus `@poll_interval`'s own
  # row-visibility margin (`systems/delivery.md`'s ORC-225 entry): a
  # bare sweep-interval threshold would only guarantee a tick *fired*,
  # not that whatever it dispatched had time to land as a visible row
  # this test can observe — `DispatchWorker.perform/1` still has to
  # run its re-validations, a `Dsl.load` and a full
  # `ContextAssembly.build` before a row exists at all.
  @quiescence_window :timer.seconds(10) + @poll_interval

  # Wider than `@poll_deadline` so a genuine timeout ends the test via
  # `flunk/1` — a real assertion failure — rather than ExUnit's own
  # 60s default kill, which would skip the `after` block below and
  # leave the test project `:active` forever (ORC-223, the incident
  # this figure was originally sized against).
  @tag timeout: :timer.minutes(7)
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
      runs = poll_until_quiescent!(base, headers, project_id)

      assert Enum.any?(runs, &(&1["tier"] == @entry_tier)),
             "expected #{@entry_tier}'s own dispatched run among the quiescent set, " <>
               "got: #{inspect(runs)}"

      for run <- runs do
        assert run["outcome"] == "success",
               "expected every dispatched run to succeed, got: #{inspect(run)}"

        assert is_binary(run["credential_used"]) and run["credential_used"] != "",
               "expected a credential_used name, got: #{inspect(run)}"

        assert is_binary(run["body_sha"]) and run["body_sha"] != "",
               "expected the committed draft's body_sha, got: #{inspect(run)}"
      end
    after
      release!(base, headers, project_id)
    end
  end

  # Quiescence (`systems/delivery.md`'s ORC-225 entry): the first poll
  # whose run-id set matches the previous poll's, with every run in
  # that set terminal, opens the quiet window; any later poll that
  # breaks either condition — a new run appears, or one drops out of
  # the terminal set — closes it and starts over. The set is
  # quiescent, and this returns it, once the window has stood open for
  # more than `@quiescence_window`. An empty run set is never
  # quiescent, however long it holds steady: a bare "the observed set
  # is stable" check is vacuously true on a project the sweeper hasn't
  # reached yet, which is exactly the shape of the bug this entry
  # closes (a suite reading green because it polled nothing). The
  # decision arithmetic itself lives in `Catapult.Generation
  # .Quiescence` (`test/support/quiescence.ex`) — this loop owns only
  # the network fetch, the sleep, and the deadline flunk, so the
  # arithmetic can be exercised directly, with synthetic run-list
  # inputs, in `test/catapult/generation/quiescence_test.exs`.
  defp poll_until_quiescent!(base, headers, project_id) do
    deadline = System.monotonic_time(:millisecond) + @poll_deadline
    poll_until_quiescent!(base, headers, project_id, deadline, nil, nil)
  end

  defp poll_until_quiescent!(base, headers, project_id, deadline, prev_ids, quiet_since) do
    runs = fetch_runs!(base, headers, project_id)
    ids = runs |> Enum.map(& &1["run_key"]) |> MapSet.new()
    now = System.monotonic_time(:millisecond)
    quiet_since = Quiescence.next_quiet_since(runs, ids, prev_ids, quiet_since, now)

    case Quiescence.outcome(quiet_since, now, deadline, @quiescence_window) do
      :quiescent ->
        runs

      :timeout ->
        flunk(
          "timed out waiting for the dispatched run set to reach quiescence, " <>
            "last observed: #{inspect(runs)}"
        )

      :continue ->
        Process.sleep(@poll_interval)
        poll_until_quiescent!(base, headers, project_id, deadline, ids, quiet_since)
    end
  end

  defp fetch_runs!(base, headers, project_id) do
    case Req.get(base <> "/dispatch/test-project/#{project_id}/runs",
           headers: headers,
           retry: false,
           receive_timeout: @request_timeout,
           connect_options: [timeout: @request_timeout]
         ) do
      {:ok, %{status: 200, body: runs}} when is_list(runs) ->
        runs

      other ->
        flunk("failed to read the dispatch-run set for #{project_id}: #{inspect(other)}")
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
