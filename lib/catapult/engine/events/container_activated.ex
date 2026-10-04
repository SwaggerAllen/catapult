defmodule Catapult.Engine.Events.ContainerActivated do
  @moduledoc """
  A minted container instance became the *current* one at its parent's
  queue (`workflow.md` #19, v5 §7.8). Version 1.

  `queue` is the instance's own first declared entry — `setup` for a
  `container`-skeleton type, the first array entry for a skeleton-less
  one — which is what makes "`setup` runs once, at activation" true
  without leaning on mint timing. The name is carried on the event
  rather than re-derived on read for the same reason every other event
  here carries its own payload: the reducer resolves bundle semantics
  at the event's own sequence, never from whatever `core_dsl`
  currently has loaded (`systems/engine.md`).
  """

  @enforce_keys [:project_id, :container_id, :queue]
  @derive Jason.Encoder
  defstruct [:project_id, :container_id, :queue, :actor_id]

  @type t :: %__MODULE__{
          project_id: binary(),
          container_id: binary(),
          queue: String.t(),
          actor_id: binary() | nil
        }
end
