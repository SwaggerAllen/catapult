defmodule Catapult.Generation.SweeperTest do
  @moduledoc """
  ORC-224: a test project must read unsweepable from the moment it's
  minted, not only once released or deleted — the window
  `Provisioning.provision/1` used to leave open between minting the
  row (`Store.mint_test_project/2`) and finishing the writes that
  describe it. Drives the real `Sweeper` GenServer's own tick under a
  throwaway name (the already-running `:generation_sweeper` is this
  application's, ticking on its own schedule — the same isolation
  `Catapult.Engine.SweeperTest` uses), offline against
  `Catapult.Delivery.HostPort.Fake` (conventions §9).

  The assertion is on the dispatch itself — `Oban.drain_queue/1`
  actually running whatever the tick enqueued, then a read of
  `delivery_dispatch_runs` (`Store.terminal_dispatch_status/2`, the
  fake's own recorded call) — never on the project's own
  `test_project_state`, which reads the same whether or not a tick
  actually skipped it.
  """

  use Catapult.DataCase, async: false

  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Generation.Sweeper
  alias Ecto.Adapters.SQL.Sandbox

  @feature_expansion_body File.read!(
                            Path.join(
                              __DIR__,
                              "fixtures/toy_seed/feature_expansion.xml"
                            )
                          )

  setup do
    Sandbox.mode(Catapult.Repo, {:shared, self()})
    on_exit(fn -> Sandbox.mode(Catapult.Repo, :manual) end)

    Application.put_env(:catapult, :fake_dispatch_result, fn _request ->
      %{
        status: :success,
        body: @feature_expansion_body,
        credential_used: "claude_code_oauth_token"
      }
    end)

    on_exit(fn -> Application.delete_env(:catapult, :fake_dispatch_result) end)
    :ok
  end

  test "a minted-but-not-activated test project is skipped; an activated one dispatches" do
    project_id = "sweep-provisioning-#{System.unique_integer([:positive])}"

    DeliveryStore.mint_test_project(project_id)
    DeliveryStore.put_project_binding(project_id, "SwaggerAllen", "catapult-test")

    {:ok, pid} = start_supervised({Sweeper, name: __MODULE__})

    tick!(pid)
    assert %{success: 0} = Oban.drain_queue(queue: :generation_dispatch)
    assert DeliveryStore.terminal_dispatch_status(project_id, "feature_expansion") == nil

    assert DeliveryStore.activate_test_project(project_id) == :ok

    tick!(pid)
    # An empty project has more than one organically-ready root tier
    # (`feature_expansion` alongside others this test doesn't seed
    # bodies for) — every job still runs, so `discard`/`failure` stay
    # zero; only `feature_expansion`'s own canned body matches its
    # grammar, which is the dispatch this test cares about.
    assert %{discard: 0, failure: 0, success: success} =
             Oban.drain_queue(queue: :generation_dispatch)

    assert success >= 1

    assert %{status: :completed} =
             DeliveryStore.terminal_dispatch_status(project_id, "feature_expansion")
  end

  # Sends `:tick` and blocks until the GenServer has processed it —
  # `:sys.get_state/1` is itself a message to the same process from
  # the same sender, so Erlang's per-pair FIFO delivery guarantees it
  # lands, and is handled, after the `:tick` already in the mailbox.
  defp tick!(pid) do
    send(pid, :tick)
    :sys.get_state(pid)
    :ok
  end
end
