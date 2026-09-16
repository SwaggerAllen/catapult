defmodule Catapult.Engine.Events.ContainerMinted do
  @moduledoc """
  A container instance exists (`workflow.md` #19, v5 §7.8). Version 1.

  **Mint is not activation.** Work gets scheduled into a milestone long
  before that milestone opens — grooming the next milestone's `prep`
  during the current one's own `main` is exactly what this design wants
  to allow — so an instance's existence cannot hinge on a step internal
  to it. This event says the instance exists and accepts work into its
  own future queues; `Catapult.Engine.Events.ContainerActivated` is the
  separate, later fact that it is the *current* one.

  `parent_container_id`/`parent_queue` are `nil` for the outermost
  instance — the project's own, minted from the workflow bundle's
  `entry:` type (`workflow.md` #2) with nothing above it — and set for
  every nested one, naming the queue entry whose `flow:` resolved to
  this container's type.
  """

  @enforce_keys [:project_id, :container_id, :type_name]
  @derive Jason.Encoder
  defstruct [
    :project_id,
    :container_id,
    :type_name,
    :parent_container_id,
    :parent_queue,
    :actor_id
  ]

  @type t :: %__MODULE__{
          project_id: binary(),
          container_id: binary(),
          type_name: String.t(),
          parent_container_id: binary() | nil,
          parent_queue: String.t() | nil,
          actor_id: binary() | nil
        }
end
