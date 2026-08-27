defmodule Catapult.Engine.Application do
  @moduledoc """
  The Commanded application (`systems/engine.md`): supervises the
  env-switched event store adapter (v5 §2.4 —
  `Commanded.EventStore.Adapters.InMemory` in test, the Postgres-backed
  `Catapult.Engine.EventStore` in dev/prod; `config/{dev,test,prod}
  .exs`) and every event handler subscribed against it.

  **Deliberately no `router(Catapult.Engine.Router)` call.** That macro
  (`Commanded.Commands.CompositeRouter.router/1`) reads
  `Router.__registered_commands__/0` at *this module's own compile
  time*, which is a genuine compile-time dependency on the router —
  the root project's `mix xref graph --label compile-connected
  --fail-above 0` gate (conventions §2, ORC-21/ORC-49) is armed at
  zero and cannot be raised by a ticket.
  `Catapult.Engine.Router` names this application directly
  (`use Commanded.Commands.Router, application: __MODULE__` there) and
  is dispatched through on its own — `Catapult.Engine.Router
  .dispatch/1,2` — rather than through an
  `Catapult.Engine.Application.dispatch/1` this module never defines.
  """

  use Commanded.Application, otp_app: :catapult
end
