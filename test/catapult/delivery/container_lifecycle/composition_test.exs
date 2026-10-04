defmodule Catapult.Delivery.ContainerLifecycle.CompositionTest do
  @moduledoc """
  Composition proposes and never commits (v5 §7.8), and proposes off
  structured signals rather than off a flat backlog view that cannot
  see why a work item is not ready.
  """

  use Catapult.DataCase, async: true

  alias Catapult.Delivery.ContainerLifecycle.Composition
  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Dsl
  alias Catapult.Dsl.Workflow
  alias Catapult.Engine.Store

  @project "comp-project"

  setup do
    assert {:ok, %{workflow: %Workflow{} = workflow}} = Dsl.load(".")

    Store.upsert_node(%{
      id: "entry",
      project_id: @project,
      tier: "sysarch",
      scope_key: %{},
      status: :absent
    })

    Store.mint_container(%{
      id: "m1",
      project_id: @project,
      type_name: "milestone",
      state: :active,
      current_queue: "cleanup",
      current_queue_sequence: 9,
      minted_sequence: 1,
      activated_sequence: 2
    })

    %{workflow: workflow, container: Store.get_container(@project, "m1")}
  end

  defp unscheduled!(id, opts \\ []) do
    Store.insert_flow(%{
      id: id,
      project_id: @project,
      flow_name: "feature",
      entry_node_id: Keyword.get(opts, :entry_node_id, "entry"),
      ticket_ref: "REF-" <> id,
      container_id: nil,
      queue: nil,
      status: :open,
      opened_sequence: 3
    })

    if kind = Keyword.get(opts, :status_kind) do
      DeliveryStore.upsert_feature_lifecycle(%{
        id: id,
        project_id: @project,
        status_kind: kind
      })
    end

    id
  end

  test "an unscheduled, unblocked work item is proposed with its reason", %{
    workflow: workflow,
    container: container
  } do
    unscheduled!("w-ready")

    assert [proposal] = Composition.propose(workflow, container)

    assert proposal.work_item_id == "w-ready"
    assert proposal.work_item_ref == "REF-w-ready"
    assert proposal.source_container_id == "m1"
    # The first non-singleton queue of the same declared type — "the
    # next container's prep", read off the array rather than hard-coded
    # to the word.
    assert proposal.target_queue == "prep"
    assert proposal.rationale =~ "not stubbed"
    assert proposal.computed_sequence == 9
  end

  test "a stubbed work item is not proposed", %{workflow: workflow, container: container} do
    # The exact case orchestration's flat backlog view kept
    # re-proposing every close: work deliberately waiting on an
    # external timeline (v5 §7.6). It is a status, not a sentence in a
    # description field.
    unscheduled!("w-stubbed", status_kind: "stubbed")

    assert Composition.candidates(workflow, container) == []
    assert Composition.propose(workflow, container) == []
  end

  test "a work item with an unresolved blocking edge is not proposed", %{
    workflow: workflow,
    container: container
  } do
    Store.upsert_node(%{
      id: "blocked-entry",
      project_id: @project,
      tier: "sysarch",
      scope_key: %{"per" => "blocked"},
      status: :absent
    })

    Store.upsert_node(%{
      id: "dependency",
      project_id: @project,
      tier: "sysarch",
      scope_key: %{"per" => "dep"},
      status: :drafted
    })

    Store.insert_edge(%{
      id: "e1",
      project_id: @project,
      edge_name: "dependency",
      type: :dependency,
      source_node_id: "blocked-entry",
      target_node_id: "dependency"
    })

    unscheduled!("w-blocked", entry_node_id: "blocked-entry")

    assert Composition.candidates(workflow, container) == []
  end

  test "a dependency that has been approved no longer blocks the proposal", %{
    workflow: workflow,
    container: container
  } do
    Store.upsert_node(%{
      id: "ok-entry",
      project_id: @project,
      tier: "sysarch",
      scope_key: %{"per" => "ok"},
      status: :absent
    })

    Store.upsert_node(%{
      id: "approved-dep",
      project_id: @project,
      tier: "sysarch",
      scope_key: %{"per" => "approved"},
      status: :approved
    })

    Store.insert_edge(%{
      id: "e2",
      project_id: @project,
      edge_name: "dependency",
      type: :dependency,
      source_node_id: "ok-entry",
      target_node_id: "approved-dep"
    })

    unscheduled!("w-unblocked", entry_node_id: "ok-entry")

    assert [%{work_item_id: "w-unblocked"}] = Composition.candidates(workflow, container)
  end

  test "a work item already assigned to a container is not re-proposed", %{
    workflow: workflow,
    container: container
  } do
    Store.insert_flow(%{
      id: "w-owned",
      project_id: @project,
      flow_name: "feature",
      entry_node_id: "entry",
      container_id: "m1",
      queue: "main",
      status: :open,
      opened_sequence: 3
    })

    assert Composition.candidates(workflow, container) == []
  end

  test "a resolved work item is not proposed", %{workflow: workflow, container: container} do
    Store.insert_flow(%{
      id: "w-done",
      project_id: @project,
      flow_name: "feature",
      entry_node_id: "entry",
      status: :completed,
      opened_sequence: 3
    })

    assert Composition.candidates(workflow, container) == []
  end

  test "proposing twice updates one row rather than duplicating it", %{
    workflow: workflow,
    container: container
  } do
    unscheduled!("w-again")

    assert [_first] = Composition.propose(workflow, container)
    assert [_second] = Composition.propose(workflow, container, sequence: 11)

    assert [row] = DeliveryStore.container_proposals(@project, "m1")
    assert row.computed_sequence == 11
  end

  test "nothing here creates a work item — proposing is not committing", %{
    workflow: workflow,
    container: container
  } do
    unscheduled!("w-proposed")

    before = @project |> Store.container_work_items("m1") |> length()
    Composition.propose(workflow, container)

    assert @project |> Store.container_work_items("m1") |> length() == before
    assert Store.queue_population(@project, "m1", "prep") == []
  end
end
