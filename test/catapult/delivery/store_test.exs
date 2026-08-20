defmodule Catapult.Delivery.StoreTest do
  use Catapult.DataCase, async: true

  alias Catapult.Delivery.Store

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
  end
end
