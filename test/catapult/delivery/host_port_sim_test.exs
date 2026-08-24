defmodule Catapult.Delivery.HostPortSimTest do
  @moduledoc """
  The sim-style test ring (`systems/delivery.md`'s ORC-31 entry): a
  full branch → PR → comment → harvest → merge-forward → merge
  scenario driven through `HostPort.Fake` alone, with no network. It
  carries no `:live` tag — nothing here crosses a real network
  boundary — and lives beside the rest of this system's suite under
  this doc's own file map, not a separate ring or `live` directory.
  Populating it is scope, not scaffolding: it is what lets protocol
  work on branches, PRs and harvesting continue to be exercised, and
  continue to be provably correct, on a day GitHub itself is down.
  """

  # Fake.Forge is reached under one well-known name
  # (`Catapult.Delivery.HostPort.Fake.Forge`), the same accommodation
  # `dispatch_worker_test.exs` already makes for `fake_dispatch_result`
  # — a single test-configured value, not one scoped per test.
  use ExUnit.Case, async: false

  alias Catapult.Delivery.HostPort.Fake
  alias Catapult.Delivery.HostPort.Fake.Forge
  alias Catapult.Delivery.HostPort.Marker

  @project "sim-project"

  setup do
    {:ok, _pid} = start_supervised({Forge, name: Forge})
    :ok
  end

  test "branch -> PR -> comment -> harvest -> merge-forward -> merge, offline" do
    # A feature branch exists off main, already carrying content —
    # there is no port operation for authoring content itself (that's
    # dispatch's own path), so the scenario seeds it directly.
    :ok = Forge.seed_branch(Forge, "main", %{"README.md" => "hello"})
    :ok = Fake.create_branch(@project, "main", "feature/orc-99")

    :ok =
      Forge.seed_branch(Forge, "feature/orc-99", %{
        "README.md" => "hello",
        "lib/widget.ex" => "defmodule Widget do\nend\n"
      })

    {:ok, %{number: pr_number, head_sha: head_sha}} =
      Fake.open_pr(@project, %{
        head: "feature/orc-99",
        base: "main",
        title: "ORC-99: add widget",
        body: "adds the widget module"
      })

    assert is_integer(pr_number)

    :ok = Fake.set_pr_labels(@project, pr_number, ["ci:code"])
    assert Forge.get_labels(Forge, pr_number) == ["ci:code"]

    # A human review comment and a bot's are both posted through the
    # identical review-comment endpoint; only the human one survives
    # the author-identity filter and is harvestable
    # (systems/delivery.md's ORC-31 harvest-filter entry).
    :ok =
      Forge.seed_review_comment(Forge, pr_number, %{
        author_login: "reviewer",
        author_type: "User",
        body: "this needs a typespec",
        path: "lib/widget.ex",
        line: 2
      })

    :ok =
      Forge.seed_review_comment(Forge, pr_number, %{
        author_login: "some-lint-bot",
        author_type: "Bot",
        body: "style nit",
        path: "lib/widget.ex",
        line: 2
      })

    {:ok, harvested} = Fake.read_review_comments(@project, pr_number, nil)
    assert [%{author_login: "reviewer", body: "this needs a typespec"}] = harvested

    # The scope-violation bounce: rendered, posted, and idempotent on
    # a retried decline path (HostPort.Marker's own moduledoc).
    :ok =
      Fake.write_marker_comment(@project, pr_number, :scope_violation, %{paths: ["lib/other.ex"]})

    :ok =
      Fake.write_marker_comment(@project, pr_number, :scope_violation, %{paths: ["lib/other.ex"]})

    assert [bounce] = Forge.list_issue_comments(Forge, pr_number)
    assert {:ok, {:scope_violation, %{paths: ["lib/other.ex"]}}} = Marker.parse(bounce.body)

    # CI reports back keyed to head SHA, regardless of base branch
    # (v5 §7.7).
    :ok =
      Forge.set_check_runs(Forge, head_sha, [
        %{name: "mix test", status: "completed", conclusion: "success"}
      ])

    assert {:ok, [%{name: "mix test", conclusion: "success"}]} =
             Fake.read_check_status(@project, head_sha)

    {:ok, diff} = Fake.read_diff(@project, pr_number)
    assert diff =~ "lib/widget.ex"

    # Main moves; the plane absorbs the drift into the open feature
    # branch continuously, in small bites (v5 §7.5).
    :ok = Forge.seed_branch(Forge, "main", %{"README.md" => "hello, updated"})
    :ok = Fake.merge_forward(@project, "main", "feature/orc-99")
    assert {:ok, files} = Forge.branch_files(Forge, "feature/orc-99")
    assert files["README.md"] == "hello, updated"

    # A conflict on the auto-merge is a real signal, never a silent
    # resolution.
    :ok = Forge.arm_merge_conflict(Forge, "main", "feature/orc-99")
    assert {:error, {:conflict, _}} = Fake.merge_forward(@project, "main", "feature/orc-99")

    # The feature PR squash-merges to main (v5 §7.5).
    :ok = Fake.merge_pr(@project, pr_number, :squash)
    assert %{state: :merged, merged_via: :squash} = Forge.get_pr(Forge, pr_number)
  end
end
