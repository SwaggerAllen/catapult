defmodule Catapult.HealthLiveTest do
  @moduledoc """
  The repo's first `:live` test (ORC-29): one smoke check of the
  reference instance's `/health` at the milestone cadence, over the real
  network, against a surface that already exists and that deploy
  detection already depends on (conventions §9, systems/foundation.md).

  A red here is a statement about the reference instance — down,
  unhealthy, or serving an unstamped build — not about whatever merged
  last; §9 routes it to a milestone blocker.
  """
  # async because the suite holds no shared state and touches no
  # database: the only resource is a remote HTTP endpoint.
  use ExUnit.Case, async: true

  @moduletag :live

  # One request, one bounded timeout, no polling and no retry. Deploy
  # detection is the plane's job and already exists (poll the App
  # Platform API, compare SHAs); a live check that waits out a rollout is
  # a second, slower deploy detector, and its long timeout is exactly
  # where a real outage hides.
  @timeout :timer.seconds(10)

  test "the reference instance serves a healthy, stamped /health" do
    base = Application.fetch_env!(:catapult, :live_base_url)

    response =
      Req.get!(base <> "/health",
        retry: false,
        receive_timeout: @timeout,
        connect_options: [timeout: @timeout]
      )

    assert response.status == 200
    assert %{"ok" => true, "sha" => sha, "components" => components} = response.body

    # Non-empty is load-bearing: `ok` is computed with Enum.all?, which
    # an empty component set satisfies vacuously.
    assert components != %{}

    assert Enum.all?(components, fn {_slug, ready?} -> ready? end),
           "components not ready: #{inspect(components)}"

    # Deliberately not `sha == System.get_env("GITHUB_SHA")`: autodeploy
    # fires on the merge to main and the boundary run follows within
    # minutes, so an equality assertion races the rollout and the failure
    # it produces is a flake — the cost ORC-29 exists to remove. "Not the
    # fallback" catches the defect that matters: an image that never went
    # through the build path.
    assert sha != "dev", "/health served the unstamped GIT_SHA fallback"
  end
end
