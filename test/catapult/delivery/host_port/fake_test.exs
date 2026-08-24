defmodule Catapult.Delivery.HostPort.FakeTest do
  @moduledoc """
  `HostPort.Fake` mirrors `HostPort.Actions`'s pagination contract —
  neither returns only a first page's worth (`systems/delivery.md`'s
  ORC-31 pagination entry). A single-page fixture can't catch a caller
  that assumes one page is everything, so these fixtures are
  deliberately sized past GitHub's own 100-per-page default.
  """

  # Fake.Forge is reached under one well-known name, so this suite
  # runs `async: false` — see `HostPort.Fake`'s own moduledoc.
  use ExUnit.Case, async: false

  alias Catapult.Delivery.HostPort.Fake
  alias Catapult.Delivery.HostPort.Fake.Forge

  @project "fake-pagination-project"

  setup do
    {:ok, _pid} = start_supervised({Forge, name: Forge})
    :ok
  end

  test "read_review_comments/3 returns every human comment past a 100-item page" do
    for i <- 1..250 do
      :ok =
        Forge.seed_review_comment(Forge, 1, %{
          author_login: "reviewer",
          author_type: "User",
          body: "comment #{i}"
        })
    end

    assert {:ok, comments} = Fake.read_review_comments(@project, 1, nil)
    assert length(comments) == 250
  end

  test "read_check_status/2 returns every check run past a 100-item page" do
    runs = for i <- 1..150, do: %{name: "job-#{i}", status: "completed", conclusion: "success"}
    :ok = Forge.set_check_runs(Forge, "deadbeef", runs)

    assert {:ok, check_runs} = Fake.read_check_status(@project, "deadbeef")
    assert length(check_runs) == 150
  end
end
