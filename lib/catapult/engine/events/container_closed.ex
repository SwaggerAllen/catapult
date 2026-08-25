defmodule Catapult.Engine.Events.ContainerClosed do
  @moduledoc """
  A container instance closed (dsl-syntax.md §15.6). Version 1.

  Two shapes, one event: a `container`-skeleton instance closes by
  reaching its fixed `terminal` kind after `cleanup` resolves; a
  skeleton-less one has no universal terminal to reach and closes when
  its own last declared entry resolves with nothing open behind it.
  Both are "this instance is done, and its parent's queue — if it has
  one — may now complete," which is the only fact anything downstream
  reads, so they are not split into two event types.
  """

  @enforce_keys [:project_id, :container_id]
  @derive Jason.Encoder
  defstruct [:project_id, :container_id, :actor_id]

  @type t :: %__MODULE__{
          project_id: binary(),
          container_id: binary(),
          actor_id: binary() | nil
        }
end
