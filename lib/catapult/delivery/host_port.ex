defmodule Catapult.Delivery.HostPort do
  @moduledoc """
  The dispatch-facing slice of the host port (`systems/generation.md`,
  `systems/delivery.md`; v5 §7.12.1): one outbound action — dispatch
  an agent run — with two adapters, exactly the "ports with fakes"
  shape every external system in this codebase follows (conventions
  §9). `Catapult.Delivery.HostPort.Actions` is the only adapter built
  here; nothing outside it may assume Actions (`systems/generation.md`
  — the execution substrate is an adapter behind this port, not the
  port itself).

  The rest of the protocol — serving the rendered context back and
  accepting the result — is inbound (the runner calls the plane), so
  it is not a port callback; `Catapult.Delivery.Dispatch` carries it,
  identically for both adapters (the fake's synchronous loop calls the
  exact same result path a real inbound HTTP call would).

  **Second operation, ORC-10:** `reset_repo/2` resets a bound repo's
  *fixture* content — never generated artifacts, which still land only
  through `Dispatch`'s result-report path into the plane's own store
  (`systems/delivery.md`'s ORC-10 entry). A bound repo has to carry a
  `workflow_dispatch` file before GitHub accepts a dispatch to it at
  all, and no role in this pipeline has a route to author a file
  inside a *different* repository, so the plane writes it there
  instead: the caller hands over the exact repo-relative paths and
  content to write (never read off this module's own disk — a fixture
  is the caller's fact, not the port's), and this operation overwrites
  each one. `HostPort.Fake` implements this too, so the offline chain
  test exercises the same reset path a live run does rather than a
  live-only mechanism.
  """

  @type request :: %{
          project_id: binary(),
          node_id: binary(),
          tier: String.t(),
          scope_key: map(),
          root_tag: String.t(),
          rendered_prompt: String.t(),
          credential_name: String.t()
        }

  @type files :: %{String.t() => String.t()}

  @callback dispatch_run(request()) :: {:ok, %{run_key: binary()}} | {:error, term()}
  @callback reset_repo(project_id :: binary(), files()) :: :ok | {:error, term()}
end
