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
        credential_sent: "claude_code_oauth_token"
      })

      assert %{status: :dispatched, github_run_id: nil} = Store.get_dispatch_run(run_key)

      Store.bind_github_run_id(run_key, "12345")
      assert %{status: :context_fetched, github_run_id: "12345"} = Store.get_dispatch_run(run_key)

      # A second bind is a no-op — a run's identity, once claimed, is fixed.
      Store.bind_github_run_id(run_key, "99999")
      assert %{github_run_id: "12345"} = Store.get_dispatch_run(run_key)

      Store.complete_dispatch_run(run_key, :completed)
      assert %{status: :completed} = Store.get_dispatch_run(run_key)
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
        credential_sent: "claude_code_oauth_token"
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
        credential_sent: "claude_code_oauth_token"
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
        credential_sent: "claude_code_oauth_token"
      })

      assert [%{node_id: "n1"}, %{node_id: "n2"}] = Store.dispatch_runs_for_flow("p1", "f1")
    end
  end
end
