defmodule Catapult.Engine.Projector do
  @moduledoc """
  Applies `Catapult.Engine.Reducer` to every committed event
  (`systems/engine.md`): a `Commanded.Event.Handler` with `:strong`
  consistency, so a caller dispatching with `consistency: :strong`
  (the default a command-edge caller should use) reads its own write
  back from the projections it just updated — the closest match to v4
  §A.3.2's "single Postgres transaction" framing Commanded's own
  primitives offer, without literally sharing one transaction across
  two connection pools (`Catapult.Repo`'s and the event store's own).
  """

  # `name:` is Commanded's event-store subscription identity, not a
  # `Process.register/2` name — but the audit's AST-grade ban on
  # `name: __MODULE__` (conventions §5) doesn't distinguish the two, so
  # a plain atom is used instead and registered through `processes/0`
  # like any other placement decision (`Catapult.Engine`).
  use Commanded.Event.Handler,
    application: Catapult.Engine.Application,
    name: :engine_projector,
    consistency: :strong

  alias Catapult.Engine.Reducer

  def handle(event, metadata), do: Reducer.apply(event, metadata)
end
