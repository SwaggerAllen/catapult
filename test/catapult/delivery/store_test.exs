defmodule Catapult.Delivery.StoreTest do
  use Catapult.DataCase, async: true

  alias Catapult.Delivery.Store
  alias Catapult.Engine.Store, as: EngineStore

  describe "project bindings" do
    test "an unbound project resolves to nil" do
      assert Store.get_project_binding("no-such-project") == nil
    end

    test "put_project_binding/3 is an upsert" do
      Store.put_project_binding("p1", "acme", "widgets")
      assert %{repo_owner: "acme", repo_name: "widgets"} = Store.get_project_binding("p1")

      Store.put_project_binding("p1", "acme", "gadgets")
      assert %{repo_owner: "acme", repo_name: "gadgets"} = Store.get_project_binding("p1")
    end
  end

  describe "dispatch runs" do
    test "insert, bind, and complete a run" do
      run_key = Ecto.UUID.generate()

      Store.insert_dispatch_run(%{
        id: run_key,
        project_id: "p1",
        node_id: "n1",
        tier: "comp",
        scope_key: %{},
        repo_owner: "acme",
        repo_name: "widgets",
        root_tag: "comp",
        rendered_prompt: "hello",
        credential_sent: ["claude_code_oauth_token"]
      })

      assert %{status: :dispatched, github_run_id: nil} = Store.get_dispatch_run(run_key)

      Store.bind_github_run_id(run_key, "12345")
      assert %{status: :context_fetched, github_run_id: "12345"} = Store.get_dispatch_run(run_key)

      # A second bind is a no-op — a run's identity, once claimed, is fixed.
      Store.bind_github_run_id(run_key, "99999")
      assert %{github_run_id: "12345"} = Store.get_dispatch_run(run_key)

      Store.complete_dispatch_run(run_key, :completed, :success, "claude_code_oauth_token")

      assert %{status: :completed, outcome: :success, credential_used: "claude_code_oauth_token"} =
               Store.get_dispatch_run(run_key)
    end
  end

  describe "draft bodies" do
    test "put then get, and put is an upsert" do
      assert Store.get_draft_body("p1", "n1") == nil

      Store.put_draft_body("p1", "n1", "first body", "sha1")
      assert Store.get_draft_body("p1", "n1") == "first body"

      Store.put_draft_body("p1", "n1", "second body", "sha2")
      assert Store.get_draft_body("p1", "n1") == "second body"
    end

    test "a first commit has no previous body, and a second shifts the first into it" do
      assert Store.get_previous_draft_body("p1", "n1") == nil

      Store.put_draft_body("p1", "n1", "first body", "sha1")
      assert Store.get_previous_draft_body("p1", "n1") == nil

      Store.put_draft_body("p1", "n1", "second body", "sha2")
      assert Store.get_previous_draft_body("p1", "n1") == "first body"
      assert Store.get_draft_body("p1", "n1") == "second body"

      # A third commit shifts again — one previous, never a log.
      Store.put_draft_body("p1", "n1", "third body", "sha3")
      assert Store.get_previous_draft_body("p1", "n1") == "second body"
      assert Store.get_draft_body("p1", "n1") == "third body"
    end
  end

  describe "the intake raft" do
    test "pin_input_documents/3 tags each file by its stem, and both reads order by filename" do
      Store.pin_input_documents("p1", "sha1", %{
        "project_doc.md" => "the project doc",
        "non_goals.md" => "the non-goals doc"
      })

      assert Store.get_input_documents("p1", "project_doc") == ["the project doc"]
      assert Store.get_input_documents("p1", "non_goals") == ["the non-goals doc"]
      assert Store.get_raft("p1") == ["the non-goals doc", "the project doc"]
    end

    test "an extension-stem collision under one role is two rows, filename order" do
      Store.pin_input_documents("p1", "sha1", %{
        "project_doc.md" => "markdown version",
        "project_doc.txt" => "plaintext version"
      })

      assert Store.get_input_documents("p1", "project_doc") == [
               "markdown version",
               "plaintext version"
             ]
    end

    test "a role with no pinned documents reads back empty, never blocking" do
      assert Store.get_input_documents("p1", "no_such_role") == []
      assert Store.get_raft("p1") == []
    end

    test "a second pin for a project that already has one raises rather than silently re-pinning" do
      Store.pin_input_documents("p1", "sha1", %{"project_doc.md" => "first"})

      assert_raise Ecto.ConstraintError, fn ->
        Store.pin_input_documents("p1", "sha2", %{"project_doc.md" => "second"})
      end
    end

    test "another project's raft never bleeds in" do
      Store.pin_input_documents("p1", "sha1", %{"project_doc.md" => "p1's doc"})
      Store.pin_input_documents("p2", "sha1", %{"project_doc.md" => "p2's doc"})

      assert Store.get_input_documents("p1", "project_doc") == ["p1's doc"]
      assert Store.get_input_documents("p2", "project_doc") == ["p2's doc"]
    end
  end

  describe "tickets_for_project/1" do
    test "lists every open flow, project-scoped, with its lifecycle status and entry-node argument" do
      EngineStore.upsert_node(%{
        id: "n1",
        project_id: "p1",
        tier: "feature_request_plan",
        scope_key: %{},
        status: :drafted,
        fields: %{"argument" => "Users need saved searches."}
      })

      EngineStore.insert_flow(%{
        id: "f1",
        project_id: "p1",
        flow_name: "feature",
        entry_node_id: "n1",
        ticket_ref: "ORC-1",
        status: :open,
        opened_sequence: 1
      })

      Store.upsert_feature_lifecycle(%{
        id: "f1",
        project_id: "p1",
        entry_node_id: "n1",
        status_gate: "ux-review"
      })

      assert [ticket] = Store.tickets_for_project("p1")
      assert ticket.id == "f1"
      assert ticket.ticket_ref == "ORC-1"
      assert ticket.flow_name == "feature"
      assert ticket.entry_node_id == "n1"
      assert ticket.status_gate == "ux-review"
      assert ticket.argument == "Users need saved searches."
    end

    test "a flow whose entry node declares no argument field renders a blank one" do
      EngineStore.upsert_node(%{
        id: "n2",
        project_id: "p1",
        tier: "bug_fix_plan",
        scope_key: %{},
        status: :drafted,
        fields: %{}
      })

      EngineStore.insert_flow(%{
        id: "f2",
        project_id: "p1",
        flow_name: "bug_fix",
        entry_node_id: "n2",
        status: :open,
        opened_sequence: 1
      })

      assert [ticket] = Store.tickets_for_project("p1")
      assert ticket.argument == nil
    end

    test "a completed flow is excluded, and another project's flows never bleed in" do
      EngineStore.upsert_node(%{
        id: "n3",
        project_id: "p1",
        tier: "bug_fix_plan",
        scope_key: %{},
        status: :drafted,
        fields: %{}
      })

      EngineStore.insert_flow(%{
        id: "f3",
        project_id: "p1",
        flow_name: "bug_fix",
        entry_node_id: "n3",
        status: :open,
        opened_sequence: 1
      })

      EngineStore.complete_flow("f3", 5)

      EngineStore.upsert_node(%{
        id: "n4",
        project_id: "p2",
        tier: "bug_fix_plan",
        scope_key: %{},
        status: :drafted,
        fields: %{}
      })

      EngineStore.insert_flow(%{
        id: "f4",
        project_id: "p2",
        flow_name: "bug_fix",
        entry_node_id: "n4",
        status: :open,
        opened_sequence: 1
      })

      assert Store.tickets_for_project("p1") == []
      assert [%{id: "f4"}] = Store.tickets_for_project("p2")
    end
  end

  describe "dispatch_runs_for_flow/2" do
    test "every run correlated to a flow, oldest first" do
      Store.insert_dispatch_run(%{
        id: Ecto.UUID.generate(),
        project_id: "p1",
        node_id: "n1",
        flow_id: "f1",
        tier: "comp",
        scope_key: %{},
        repo_owner: "acme",
        repo_name: "widgets",
        root_tag: "comp",
        rendered_prompt: "hello",
        credential_sent: ["claude_code_oauth_token"]
      })

      Store.insert_dispatch_run(%{
        id: Ecto.UUID.generate(),
        project_id: "p1",
        node_id: "n2",
        flow_id: "f1",
        tier: "comp",
        scope_key: %{},
        repo_owner: "acme",
        repo_name: "widgets",
        root_tag: "comp",
        rendered_prompt: "hello again",
        credential_sent: ["claude_code_oauth_token"]
      })

      # A different flow's own run never bleeds in.
      Store.insert_dispatch_run(%{
        id: Ecto.UUID.generate(),
        project_id: "p1",
        node_id: "n3",
        flow_id: "f2",
        tier: "comp",
        scope_key: %{},
        repo_owner: "acme",
        repo_name: "widgets",
        root_tag: "comp",
        rendered_prompt: "unrelated",
        credential_sent: ["claude_code_oauth_token"]
      })

      assert [%{node_id: "n1"}, %{node_id: "n2"}] = Store.dispatch_runs_for_flow("p1", "f1")
    end
  end

  describe "list_bound_project_ids/0" do
    test "every project id ever bound to a repo" do
      Store.put_project_binding("bound-1", "acme", "widgets")
      Store.put_project_binding("bound-2", "acme", "gadgets")

      assert "bound-1" in Store.list_bound_project_ids()
      assert "bound-2" in Store.list_bound_project_ids()
    end
  end

  describe "terminal_dispatch_status/2" do
    test "nil when the tier has never been dispatched" do
      assert Store.terminal_dispatch_status("no-such-project", "comp") == nil
    end

    test "status, outcome, credential_used, node_id and the node's own body_sha" do
      EngineStore.upsert_node(%{
        id: "n1",
        project_id: "p1",
        tier: "comp",
        scope_key: %{},
        status: :drafted,
        fields: %{},
        body_sha: "sha-of-the-committed-draft"
      })

      Store.insert_dispatch_run(%{
        id: Ecto.UUID.generate(),
        project_id: "p1",
        node_id: "n1",
        tier: "comp",
        scope_key: %{},
        repo_owner: "acme",
        repo_name: "widgets",
        root_tag: "comp",
        rendered_prompt: "irrelevant",
        credential_sent: ["claude_code_oauth_token"]
      })

      # A second, more recent run on the same tier is the one this
      # read surfaces — "most recent", not "first".
      newer_run_key = Ecto.UUID.generate()

      Store.insert_dispatch_run(%{
        id: newer_run_key,
        project_id: "p1",
        node_id: "n1",
        tier: "comp",
        scope_key: %{},
        repo_owner: "acme",
        repo_name: "widgets",
        root_tag: "comp",
        rendered_prompt: "irrelevant",
        credential_sent: ["claude_code_oauth_token"]
      })

      Store.complete_dispatch_run(newer_run_key, :completed, :success, "claude_code_oauth_token")

      assert Store.terminal_dispatch_status("p1", "comp") == %{
               status: :completed,
               outcome: :success,
               credential_used: "claude_code_oauth_token",
               node_id: "n1",
               body_sha: "sha-of-the-committed-draft"
             }
    end
  end

  describe "the test-project lifecycle (ORC-216)" do
    test "an ordinary project (no row at all) is sweepable" do
      assert Store.sweepable_project?("no-such-project") == true
    end

    test "mint_test_project/2 mints provisioning, unsweepable until activated (ORC-224)" do
      minted = Store.mint_test_project("tp1")
      assert minted.test_project_state == :provisioning
      assert Store.sweepable_project?("tp1") == false

      assert Store.activate_test_project("tp1") == :ok
      assert Store.sweepable_project?("tp1") == true
    end

    test "mint_test_project/2 releases whichever was active or still provisioning before" do
      Store.mint_test_project("tp1")
      Store.activate_test_project("tp1")
      assert Store.sweepable_project?("tp1") == true

      # tp2 minted straight to :provisioning, so not sweepable yet either.
      second = Store.mint_test_project("tp2")
      assert second.test_project_state == :provisioning
      assert Store.sweepable_project?("tp2") == false

      # Minting tp2 released tp1, even though tp1 was active.
      assert Store.sweepable_project?("tp1") == false
      assert "tp1" in Store.list_released_test_projects()
    end

    test "mint_test_project/2 reclaims a row a crashed provisioning attempt stranded at :provisioning" do
      Store.mint_test_project("tp-stranded")
      # Never activated or released — the shape a raised failure inside
      # `reset_and_intake/2` leaves behind (this doc's own moduledoc).

      Store.mint_test_project("tp-fresh")
      assert "tp-stranded" in Store.list_released_test_projects()
    end

    test "activate_test_project/1 only promotes a currently-provisioning row, never a released one" do
      Store.mint_test_project("tp-act")
      Store.release_test_project("tp-act")
      assert Store.sweepable_project?("tp-act") == false

      # A retried/duplicated activate call must not resurrect a
      # terminal-for-now row a concurrent release already moved past.
      assert Store.activate_test_project("tp-act") == :ok
      assert Store.sweepable_project?("tp-act") == false
    end

    test "release_test_project/1 is idempotent and a no-op on an unminted project" do
      assert Store.release_test_project("no-such-project") == :ok

      Store.mint_test_project("tp3")
      assert Store.release_test_project("tp3") == :ok
      assert Store.release_test_project("tp3") == :ok
      assert Store.sweepable_project?("tp3") == false
    end

    test "release_test_project/1 releases a still-provisioning project too (ORC-224)" do
      Store.mint_test_project("tp-release-provisioning")
      assert Store.release_test_project("tp-release-provisioning") == :ok
      assert "tp-release-provisioning" in Store.list_released_test_projects()
    end

    test "delete_test_project/1 purges delivery-owned rows and tombstones the project" do
      Store.mint_test_project("tp4")
      Store.put_project_binding("tp4", "acme", "widgets")
      Store.release_test_project("tp4")

      assert Store.delete_test_project("tp4") == :ok
      assert Store.get_project_binding("tp4") == nil
      assert Store.sweepable_project?("tp4") == false
      refute "tp4" in Store.list_released_test_projects()
    end

    test "delete_test_project/1 purges all eight delivery-owned tables, not just bindings" do
      Store.mint_test_project("tp5")
      Store.put_project_binding("tp5", "acme", "widgets")

      Store.insert_dispatch_run(%{
        id: Ecto.UUID.generate(),
        project_id: "tp5",
        node_id: "n1",
        tier: "comp",
        scope_key: %{},
        repo_owner: "acme",
        repo_name: "widgets",
        root_tag: "comp",
        rendered_prompt: "hello",
        credential_sent: ["claude_code_oauth_token"]
      })

      Store.pin_input_documents("tp5", "sha1", %{"project_doc.md" => "content"})
      Store.put_draft_body("tp5", "n1", "body", "body-sha")

      Store.upsert_feature_lifecycle(%{
        id: "flow1",
        project_id: "tp5",
        status_kind: "pending"
      })

      Store.upsert_feature_publication(%{
        id: "flow1",
        project_id: "tp5",
        branch_name: "feature/x",
        base_ref: "main",
        pr_number: 1
      })

      Store.upsert_container_proposal(%{
        id: "prop1",
        project_id: "tp5",
        source_container_id: "c1",
        target_queue: "prep",
        work_item_id: "w1"
      })

      Store.upsert_artifact_push(%{
        project_id: "tp5",
        node_id: "n1",
        flow_id: "flow1",
        tier: "comp",
        path: "docs/x.md",
        body_sha: "body-sha"
      })

      Store.release_test_project("tp5")
      assert Store.delete_test_project("tp5") == :ok

      import Ecto.Query
      alias Catapult.Delivery.Store.ArtifactPush
      alias Catapult.Delivery.Store.ContainerProposal
      alias Catapult.Delivery.Store.DispatchRun
      alias Catapult.Delivery.Store.DraftBody
      alias Catapult.Delivery.Store.FeatureLifecycle
      alias Catapult.Delivery.Store.FeaturePublication
      alias Catapult.Delivery.Store.InputDocument
      alias Catapult.Delivery.Store.ProjectBinding

      for schema <- [
            ProjectBinding,
            DispatchRun,
            InputDocument,
            DraftBody,
            FeatureLifecycle,
            FeaturePublication,
            ContainerProposal,
            ArtifactPush
          ] do
        remaining = Catapult.Repo.all(from(r in schema, where: r.project_id == "tp5"))

        assert remaining == [],
               "expected #{inspect(schema)} to be purged, found #{inspect(remaining)}"
      end

      assert Store.sweepable_project?("tp5") == false
    end
  end

  describe "stub_mode (ORC-223)" do
    test "an ordinary project (no row at all) is never stub mode" do
      assert Store.stub_mode?("no-such-project") == false
    end

    test "mint_test_project/2 defaults to stub mode true" do
      Store.mint_test_project("tp-stub-default")
      assert Store.stub_mode?("tp-stub-default") == true
    end

    test "mint_test_project/2 persists an explicit stub_mode" do
      Store.mint_test_project("tp-stub-false", false)
      assert Store.stub_mode?("tp-stub-false") == false
    end
  end

  describe "in_flight_dispatch?/4 (ORC-223)" do
    defp seed_dispatch_run(project_id, tier, scope_key) do
      Store.insert_dispatch_run(%{
        id: Ecto.UUID.generate(),
        project_id: project_id,
        node_id: "n1",
        tier: tier,
        scope_key: scope_key,
        repo_owner: "acme",
        repo_name: "widgets",
        root_tag: "comp",
        rendered_prompt: "hello",
        credential_sent: ["claude_code_oauth_token"]
      })
    end

    test "false with no dispatch run at all" do
      refute Store.in_flight_dispatch?("no-such-project", "vocab", %{}, ~U[2020-01-01 00:00:00Z])
    end

    test "true for a non-terminal run at or after the cutoff" do
      seed_dispatch_run("p-inflight", "vocab", %{"id" => "auth"})

      assert Store.in_flight_dispatch?(
               "p-inflight",
               "vocab",
               %{"id" => "auth"},
               ~U[2020-01-01 00:00:00Z]
             )
    end

    test "false once the run completes" do
      run_key = Ecto.UUID.generate()

      Store.insert_dispatch_run(%{
        id: run_key,
        project_id: "p-done",
        node_id: "n1",
        tier: "vocab",
        scope_key: %{"id" => "auth"},
        repo_owner: "acme",
        repo_name: "widgets",
        root_tag: "comp",
        rendered_prompt: "hello",
        credential_sent: ["claude_code_oauth_token"]
      })

      Store.complete_dispatch_run(run_key, :completed, :success, "claude_code_oauth_token")

      refute Store.in_flight_dispatch?(
               "p-done",
               "vocab",
               %{"id" => "auth"},
               ~U[2020-01-01 00:00:00Z]
             )
    end

    test "false once the row ages past the cutoff" do
      seed_dispatch_run("p-stale", "vocab", %{"id" => "auth"})

      future_cutoff = DateTime.add(DateTime.utc_now(), 3600, :second)
      refute Store.in_flight_dispatch?("p-stale", "vocab", %{"id" => "auth"}, future_cutoff)
    end

    test "neither a different scope_key nor a different tier bleeds in" do
      seed_dispatch_run("p-scoped", "vocab", %{"id" => "auth"})

      refute Store.in_flight_dispatch?(
               "p-scoped",
               "vocab",
               %{"id" => "other"},
               ~U[2020-01-01 00:00:00Z]
             )

      refute Store.in_flight_dispatch?(
               "p-scoped",
               "sysarch",
               %{"id" => "auth"},
               ~U[2020-01-01 00:00:00Z]
             )
    end
  end
end
