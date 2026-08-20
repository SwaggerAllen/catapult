defmodule Catapult.Engine.EventStore do
  @moduledoc """
  The persistent adapter's own EventStore module (v5 §2.4): a
  dedicated Postgres schema (`priv/repo/migrations_infra`'s
  `AddEventStore` migration), reached only through this module and
  Commanded's API — application code never queries its tables
  directly (conventions §6).

  Not started for its own sake: dev and prod wire it in via
  `Catapult.Engine.Application`'s `event_store:` config
  (`config/dev.exs`, `config/prod.exs`); test uses
  `Commanded.EventStore.Adapters.InMemory` instead, so this module's
  `start_link/1` is only ever called by the adapter, never listed in
  `Catapult.Engine.children/0` directly.
  """

  use EventStore, otp_app: :catapult

  alias Catapult.Config
  alias Catapult.Config.Secret

  # No `@impl EventStore` here: `use EventStore` itself injects a
  # `defdelegate ack/2` with no `@impl` of its own, and annotating any
  # one callback in this module makes the compiler demand one on every
  # implementation of the behaviour, library-generated code included.
  def init(config) do
    # Same seam as `Catapult.Repo.init/2`: connection settings are
    # assembled from foundation's already-declared `:database_url`
    # (systems/foundation.md), never re-declared here. `schema:` is
    # the reserved-prefix namespacing this library's own tables use
    # (conventions §6's `eventstore.*`).
    Catapult.Boot.load!()

    {:ok,
     config
     |> Keyword.merge(Secret.unwrap(Config.fetch!(:foundation, :database_url)))
     |> Keyword.put(:schema, "eventstore")
     # Commanded's own serializer (its moduledoc's own recommendation):
     # it round-trips the versioned event structs this component
     # emits, including their atom-keyed fields, which the library's
     # own default `EventStore.JsonSerializer` does not attempt.
     |> Keyword.put(:serializer, Commanded.Serialization.JsonSerializer)}
  end
end
