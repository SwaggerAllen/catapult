defmodule Catapult.Generation.DispatchWorkerTest do
  use Catapult.DataCase, async: false

  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Engine.Commands.RecordRunFailure
  alias Catapult.Engine.Router
  alias Catapult.Engine.Store
  alias Catapult.Generation.DispatchWorker
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    Sandbox.mode(Catapult.Repo, {:shared, self()})
    on_exit(fn -> Sandbox.mode(Catapult.Repo, :manual) end)

    Application.put_env(:catapult, :fake_dispatch_result, fn _request ->
      %{
        status: :success,
        body: "<vocab-entry><definition>x</definition></vocab-entry>",
        credential_used: "x"
      }
    end)

    on_exit(fn -> Application.delete_env(:catapult, :fake_dispatch_result) end)
    on_exit(fn -> Application.delete_env(:catapult, :generation_fake_clock) end)
    :ok
  end

  defp seed_in_flight_run(project_id, node_id, tier, scope_key) do
    DeliveryStore.insert_dispatch_run(%{
      id: Ecto.UUID.generate(),
      project_id: project_id,
      node_id: node_id,
      tier: tier,
      scope_key: scope_key,
      repo_owner: "acme",
      repo_name: "widgets",
      root_tag: "vocab-entry",
      rendered_prompt: "already dispatched",
      credential_sent: ["claude_code_oauth_token"]
    })
  end

  defp seed_ready_vocab(project_id, node_id) do
    Store.upsert_node(%{
      id: "fe1",
      project_id: project_id,
      tier: "feature_expansion",
      scope_key: %{},
      status: :approved,
      fields: %{}
    })

    Store.mint_node(%{
      id: node_id,
      project_id: project_id,
      tier: "vocab",
      scope_key: %{"id" => "auth"},
      parent_node_id: "fe1",
      status: :absent
    })
  end

  test "dispatches a still-ready scope through the configured host port" do
    project_id = "dw-#{System.unique_integer([:positive])}"
    seed_ready_vocab(project_id, "vocab:auth")

    args = %{"project_id" => project_id, "tier" => "vocab", "scope_key" => %{"id" => "auth"}}
    assert :ok = Oban.Testing.perform_job(DispatchWorker, args, [])

    assert Store.get_node(project_id, "vocab:auth").status == :drafted
  end

  test "skips a scope that is no longer ready" do
    project_id = "dw-#{System.unique_integer([:positive])}"
    # No node minted at all — the scope was never ready in the first place.
    args = %{"project_id" => project_id, "tier" => "vocab", "scope_key" => %{"id" => "ghost"}}
    assert :ok = Oban.Testing.perform_job(DispatchWorker, args, [])
  end

  test "skips (never redispatches) a scope with two prior limit-class failures" do
    project_id = "dw-#{System.unique_integer([:positive])}"
    seed_ready_vocab(project_id, "vocab:auth")

    for run_id <- ["r1", "r2"] do
      :ok =
        Router.dispatch(
          %RecordRunFailure{
            project_id: project_id,
            node_id: "vocab:auth",
            tier: "vocab",
            scope_key: %{"id" => "auth"},
            run_id: run_id,
            reason: "usage_limit",
            occurred_at: ~U[2026-01-01 00:00:00Z]
          },
          consistency: :strong
        )
    end

    args = %{"project_id" => project_id, "tier" => "vocab", "scope_key" => %{"id" => "auth"}}
    assert :ok = Oban.Testing.perform_job(DispatchWorker, args, [])

    # Blocked — never committed, and no dispatch-run record was opened.
    assert Store.get_node(project_id, "vocab:auth").status == :absent
  end

  describe "the in-flight guard (ORC-223)" do
    test "skips (never redispatches) a scope with an in-flight, non-stale dispatch run" do
      project_id = "dw-#{System.unique_integer([:positive])}"
      seed_ready_vocab(project_id, "vocab:auth")
      seed_in_flight_run(project_id, "vocab:auth", "vocab", %{"id" => "auth"})

      Application.put_env(:catapult, :generation_fake_clock, DateTime.utc_now())

      args = %{"project_id" => project_id, "tier" => "vocab", "scope_key" => %{"id" => "auth"}}
      assert :ok = Oban.Testing.perform_job(DispatchWorker, args, [])

      # Skipped — never committed, and no second dispatch run was opened.
      assert Store.get_node(project_id, "vocab:auth").status == :absent
    end

    test "redispatches once the in-flight run ages past the staleness cutoff" do
      project_id = "dw-#{System.unique_integer([:positive])}"
      seed_ready_vocab(project_id, "vocab:auth")
      seed_in_flight_run(project_id, "vocab:auth", "vocab", %{"id" => "auth"})

      # Past the default three-hour staleness window (GENERATION_DISPATCH_STALE_AFTER_MS) —
      # the same dead-run age-out this guard exists to provide, with
      # nothing writing to the stale row to make it happen.
      Application.put_env(
        :catapult,
        :generation_fake_clock,
        DateTime.add(DateTime.utc_now(), 4 * 3600, :second)
      )

      args = %{"project_id" => project_id, "tier" => "vocab", "scope_key" => %{"id" => "auth"}}
      assert :ok = Oban.Testing.perform_job(DispatchWorker, args, [])

      assert Store.get_node(project_id, "vocab:auth").status == :drafted
    end

    test "a different scope's in-flight run never blocks this one" do
      project_id = "dw-#{System.unique_integer([:positive])}"
      seed_ready_vocab(project_id, "vocab:auth")
      seed_in_flight_run(project_id, "vocab:other", "vocab", %{"id" => "other"})

      Application.put_env(:catapult, :generation_fake_clock, DateTime.utc_now())

      args = %{"project_id" => project_id, "tier" => "vocab", "scope_key" => %{"id" => "auth"}}
      assert :ok = Oban.Testing.perform_job(DispatchWorker, args, [])

      assert Store.get_node(project_id, "vocab:auth").status == :drafted
    end
  end
end
