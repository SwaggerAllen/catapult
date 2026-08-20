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

  @callback dispatch_run(request()) :: {:ok, %{run_key: binary()}} | {:error, term()}
end
