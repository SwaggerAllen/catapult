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
  `feature_expansion` — the toy chain's own entry tier and this walk's
  first dispatch — a full downward-cascade walk of the toy raft against
  real GitHub Actions runs, `Provisioning.approve_drafts/2` approving
  every drafted node the walk produces since no human is in this run to
  do it, and the tier set the run actually reached, not a fixed one, as
  what a passing run demonstrates.

  **ORC-230: an actor for the unattended run, and assertions that name
  the walk rather than accept whatever stopped.** Quiescence — the
  run-id set holding steady with everything terminal — cannot tell a
  chain that finished from one that merely stalled: a permanently
  blocked graph satisfies it as comfortably as a completed one, which
  is exactly what happened before this ticket. Nothing ever dispatched
  `ApproveDraft` in an unattended run
  (`Catapult.Delivery.DraftResolution` only reacts to a human's
  `GateApproved`), so every tier gated on an ancestor's `:approved`
  status stayed permanently unready, and the two-round walk that
  produced was the ceiling, not evidence of a finished chain. Now that
  `Provisioning.approve_drafts/2` exists as the unattended run's own
  actor (test scaffolding, not product semantics —
  the threshold-based-gating decision stays parked; this reads no review score and approves unconditionally), the
  poll loop alternates: poll `runs/2`
  (`/dispatch/test-project/:project_id/runs`,
  `systems/delivery.md`'s ORC-230 entry) until its own `remaining`
  count reads zero — nothing left to dispatch and nothing running —
  call `approve_drafts/2` once, and poll again. It stops only when a
  full cycle leaves `remaining` at zero **and** `approve_drafts/2`
  reports zero approvals: together, nothing dispatchable, nothing
  running, and nothing sitting `:drafted` waiting on an approval that
  will never come from a human.

  This is deliberate, not a missed opportunity to cap it: the boundary
  pass exists to be as close to production as the toy chain gets
  without a model in the loop, so it runs the whole chain agentless
  rather than stopping at a fixed round count sized to what nobody has
  measured — the position design review settled on over a round-capped
  alternative an earlier draft of this ticket proposed. A real-model
  run confirms the production case separately and strictly afterward.

  **The assertion is that an approval produced a new dispatch, not
  merely that one node crossed into `:approved`.** `approve_drafts/2`
  dispatches `ApproveDraft` directly against every `:drafted` node, so
  one reported approval already means one node advanced — what still
  isn't proof on its own is that the approval *did* anything: a leaf
  tier's own approval unblocks nothing further downstream. So this test
  tracks `run_key`s across polls, and asserts that at least one
  `approve_drafts/2` call reporting an approval is followed, on a later
  poll, by a `run_key` that was not present before — the fact only a
  node crossing into `:approved` and becoming ready for whatever reads
  it can produce. `Provisioning` exposes no node-status read, so a new
  run is the fact this test can actually observe.

  **The tier set the walk reaches is checked against a predicate, not
  a fixed number.** `bundles/default/tiers/*.yaml`'s own shape fixes
  which tiers a complete walk dispatches: every tier the sweeper would
  ever consider (`reviews:` set, or `draft:` present with
  `generator: "llm"`) minus the ones scoped `cascade_visit` — Target,
  not Initial (`Catapult.Engine.Projections.ReadyScopes`'s own
  moduledoc) — since `ReadyScopes`'s own candidate enumeration returns
  `[]` for that scope unconditionally, so a `cascade_visit`-scoped tier
  is stub-fixtured but structurally unreachable from this walk, not
  part of the toy raft's own downward cascade. `expected_tier_names/0`
  derives that set straight off the loaded bundle rather than a
  hand-maintained list, so the assertion moves with the bundle instead
  of drifting the next time a tier is added — twenty of ORC-225's
  twenty-two stub fixtures were unreachable before this ticket, and a
  passing run here is the first observed evidence that every one of
  them the toy raft's cascade actually reaches resolves against its
  stub.

  **`Catapult.Generation.Quiescence` retired in the same change.** Its
  quiet-since arithmetic hedged a race `remaining == 0` now reads
  directly off plane state — a sweep tick that fired but had not yet
  produced a visible row. This test was its only caller; nothing in
  the tree calls `next_quiet_since/5` or `outcome/4` anymore, so
  `test/support/quiescence.ex` and its own direct-coverage test are
  deleted rather than kept alive with no caller.

  **Needs setup this environment cannot supply.** `DELIVERY_PROVISIONING_TOKEN`
  defaults to a fake string (`config/test.exs`) unless the live-suite
  job's own environment overrides it with the same value the deployed
  plane's own `DELIVERY_PROVISIONING_TOKEN` holds — see this ticket's
  hand-back for what the operator still has to wire in.
  """

  use ExUnit.Case, async: true

  alias Catapult.Config.Secret
  alias Catapult.Delivery
  alias Catapult.Dsl
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

  # ORC-230 widens what this deadline has to cover, from up to two
  # sequential rounds to the raft's full downward-cascade walk
  # (`systems/generation.md`'s own entry derives this floor: three
  # approval-gated rounds at 15 minutes, plus the longer of the two
  # post-`sysarch` branches at 12 minutes, for a 27-minute floor, plus
  # 6 minutes of headroom for the fan-out breadth a tier-depth count
  # alone cannot predict — 33 minutes).
  @poll_deadline :timer.minutes(33)

  @entry_tier "feature_expansion"

  # Wider than `@poll_deadline` so a genuine timeout ends the test via
  # `flunk/1` — a real assertion failure — rather than ExUnit's own
  # default kill, which would skip the `after` block below and leave
  # the test project `:active` forever (ORC-223, the incident this
  # figure was originally sized against).
  @tag timeout: :timer.minutes(35)
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
      runs = poll_walk!(base, headers, project_id)

      assert List.first(runs)["tier"] == @entry_tier,
             "expected #{@entry_tier} to be the walk's first dispatch, " <>
               "got: #{inspect(List.first(runs))}"

      observed_tiers = runs |> Enum.map(& &1["tier"]) |> MapSet.new()
      expected_tiers = expected_tier_names()

      assert observed_tiers == expected_tiers,
             "expected the walk to reach exactly #{inspect(Enum.sort(MapSet.to_list(expected_tiers)))}, " <>
               "got: #{inspect(Enum.sort(MapSet.to_list(observed_tiers)))}"

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

  # Alternates polling `runs/2` to `remaining == 0` with a single
  # `approve_drafts!/3` call, stopping only once a full cycle leaves
  # both zero (this module's own moduledoc). The walk's own progress
  # is threaded as a single accumulator map rather than five separate
  # arguments (credo's own arity-8 ceiling): `seen_ids` is the previous
  # poll's own `run_key` set; `awaiting_effect?` is true from the
  # moment an `approve_drafts!/3` call reports at least one approval
  # until a later poll's run set actually grows, at which point
  # `advanced?` latches — the assertion that an approval produced a new
  # dispatch, not merely that a node compare-and-swapped. `log` is
  # diagnostic only, folded into a timeout's own `flunk/1` message,
  # alongside `last_runs` — the most recently fetched `runs/2` body,
  # carried so a timeout can report the tier set observed so far and
  # each run's `duration_ms` (`systems/generation.md`'s ORC-230 entry)
  # without a doomed extra fetch against a plane that has already
  # stopped answering in time.
  defp poll_walk!(base, headers, project_id) do
    deadline = System.monotonic_time(:millisecond) + @poll_deadline

    state = %{
      seen_ids: MapSet.new(),
      awaiting_effect?: false,
      advanced?: false,
      log: [],
      last_runs: []
    }

    poll_walk!(base, headers, project_id, deadline, state)
  end

  defp poll_walk!(base, headers, project_id, deadline, state) do
    if System.monotonic_time(:millisecond) >= deadline do
      tiers_and_durations = Enum.map(state.last_runs, &{&1["tier"], &1["duration_ms"]})

      flunk(
        "timed out waiting for the toy raft's downward-cascade walk to finish — " <>
          "tier set observed so far (tier, duration_ms): #{inspect(tiers_and_durations)}; " <>
          "approve_drafts/2 calls so far (oldest first): #{inspect(Enum.reverse(state.log))}"
      )
    end

    %{"runs" => runs, "remaining" => remaining} = fetch_runs!(base, headers, project_id)
    ids = runs |> Enum.map(& &1["run_key"]) |> MapSet.new()

    advanced? =
      state.advanced? or (state.awaiting_effect? and not MapSet.subset?(ids, state.seen_ids))

    if remaining > 0 do
      Process.sleep(@poll_interval)

      next_state = %{state | seen_ids: ids, advanced?: advanced?, last_runs: runs}
      poll_walk!(base, headers, project_id, deadline, next_state)
    else
      approved = approve_drafts!(base, headers, project_id)

      if approved == 0 do
        assert advanced?,
               "expected at least one approve_drafts/2 call reporting an approval to be " <>
                 "followed by a later poll showing a new dispatched run, proving the " <>
                 "mechanism actually advanced the walk — approve_drafts/2 calls (oldest " <>
                 "first): #{inspect(Enum.reverse(state.log))}"

        runs
      else
        Process.sleep(@poll_interval)

        next_state = %{
          state
          | seen_ids: ids,
            awaiting_effect?: true,
            advanced?: advanced?,
            log: [approved | state.log],
            last_runs: runs
        }

        poll_walk!(base, headers, project_id, deadline, next_state)
      end
    end
  end

  # Every tier the sweeper would ever consider — `ready/3` and
  # `ready_review/3`'s own eligibility, replayed here rather than
  # imported (this module's own moduledoc: the same small duplication
  # `Catapult.Delivery.Provisioning`'s `remaining` computation carries)
  # — minus `cascade_visit`-scoped tiers, structurally unreachable from
  # this walk regardless of `draft:`/`reviews:` shape. Loaded straight
  # off the bundle so this assertion moves with it instead of a
  # hand-maintained list drifting the next time a tier is added.
  defp expected_tier_names do
    {:ok, %{chain: chain}} = Dsl.load(".")

    chain.tiers
    |> Enum.filter(fn {_name, tier} -> dispatchable?(tier) and tier.scope != {:cascade_visit} end)
    |> Enum.map(fn {name, _tier} -> name end)
    |> MapSet.new()
  end

  defp dispatchable?(%{reviews: reviewed}) when not is_nil(reviewed), do: true
  defp dispatchable?(%{draft: draft, generator: "llm"}) when not is_nil(draft), do: true
  defp dispatchable?(_tier), do: false

  defp fetch_runs!(base, headers, project_id) do
    case Req.get(base <> "/dispatch/test-project/#{project_id}/runs",
           headers: headers,
           retry: false,
           receive_timeout: @request_timeout,
           connect_options: [timeout: @request_timeout]
         ) do
      {:ok, %{status: 200, body: %{"runs" => runs, "remaining" => remaining}}}
      when is_list(runs) and is_integer(remaining) ->
        %{"runs" => runs, "remaining" => remaining}

      other ->
        flunk("failed to read the dispatch-run set for #{project_id}: #{inspect(other)}")
    end
  end

  defp approve_drafts!(base, headers, project_id) do
    case Req.post(base <> "/dispatch/test-project/#{project_id}/approve-drafts",
           headers: headers,
           retry: false,
           receive_timeout: @request_timeout,
           connect_options: [timeout: @request_timeout]
         ) do
      {:ok, %{status: 200, body: %{"approved" => approved}}} when is_integer(approved) ->
        approved

      other ->
        flunk("failed to approve drafts for #{project_id}: #{inspect(other)}")
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
