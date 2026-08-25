defmodule CatapultWeb.EventLogLiveTest do
  use CatapultWeb.ConnCase, async: false

  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Events.ReviewWrittenV1
  alias Catapult.Engine.Router
  alias Commanded.EventStore.EventData
  alias Commanded.Serialization.ModuleNameTypeProvider
  alias Ecto.Adapters.SQL.Sandbox

  # `:strong` consistency and shared sandbox mode: `RunFailuresTest`'s
  # own precedent (`Catapult.Engine.Reducer`'s DB write needs it).
  setup do
    Sandbox.mode(Catapult.Repo, {:shared, self()})
    on_exit(fn -> Sandbox.mode(Catapult.Repo, :manual) end)
    :ok
  end

  test "a project with no events yet renders the empty state", %{conn: conn} do
    project_id = "evlog-#{System.unique_integer([:positive])}"

    {:ok, _view, html} = live(conn, "/projects/#{project_id}/event-log")

    assert html =~ "Nothing has happened here yet"
  end

  test "a committed draft shows one row at its current, matching version", %{conn: conn} do
    project_id = "evlog-#{System.unique_integer([:positive])}"

    :ok =
      Router.dispatch(
        %CommitDraft{
          project_id: project_id,
          node_id: "n1",
          tier: "comp",
          scope_key: %{},
          draft_id: "d1",
          body_sha: "sha1",
          committed_at: ~U[2026-01-01 00:00:00Z]
        },
        consistency: :strong
      )

    {:ok, _view, html} = live(conn, "/projects/#{project_id}/event-log")

    assert html =~ "draft_committed"
    assert html =~ "v1"
    refute html =~ "recorded v"
  end

  test "a v1 review_written event discloses the upcast to v2", %{conn: conn} do
    project_id = "evlog-#{System.unique_integer([:positive])}"
    stream_id = "project-" <> project_id

    # A real draft first — the projector's reducer writes a `Review`
    # row with a `draft_id` foreign key, so an event naming a draft
    # that was never committed crashes the (shared, app-wide) projector
    # process and takes every later test's `:strong` dispatch with it.
    :ok =
      Router.dispatch(
        %CommitDraft{
          project_id: project_id,
          node_id: "n1",
          tier: "comp",
          scope_key: %{},
          draft_id: "d1",
          body_sha: "sha1",
          committed_at: ~U[2026-01-01 00:00:00Z]
        },
        consistency: :strong
      )

    v1 = %ReviewWrittenV1{
      project_id: project_id,
      draft_id: "d1",
      review_id: "r1",
      score: 0.73,
      body_sha: "sha1",
      findings: []
    }

    event = %EventData{
      event_type: ModuleNameTypeProvider.to_string(v1),
      data: v1,
      metadata: %{}
    }

    :ok =
      Commanded.EventStore.append_to_stream(Catapult.Engine.Application, stream_id, 1, [event])

    {:ok, _view, html} = live(conn, "/projects/#{project_id}/event-log")

    assert html =~ "review_written"
    assert html =~ "recorded v1"
    assert html =~ "shown v2"
  end

  test "the ticket filter narrows to one container", %{conn: conn} do
    project_id = "evlog-#{System.unique_integer([:positive])}"

    :ok =
      Router.dispatch(
        %CommitDraft{
          project_id: project_id,
          node_id: "n1",
          tier: "comp",
          scope_key: %{},
          draft_id: "d1",
          body_sha: "sha1",
          committed_at: ~U[2026-01-01 00:00:00Z]
        },
        consistency: :strong
      )

    {:ok, _view, html} = live(conn, "/projects/#{project_id}/event-log?container=no-such-ticket")

    assert html =~ "Nothing has happened here yet"
  end
end
