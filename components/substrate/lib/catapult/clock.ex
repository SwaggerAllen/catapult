defmodule Catapult.Clock do
  @moduledoc """
  The injected clock (conventions §9): `DateTime.utc_now/0` is banned in
  domain code by the audit's grep; domain code takes the clock as a
  dependency so tests are deterministic. `Catapult.Clock.System` is the
  runtime implementation.
  """

  @callback utc_now() :: DateTime.t()

  defmodule System do
    @moduledoc "The runtime clock."
    @behaviour Catapult.Clock
    @impl true
    # catapult:allow utc_now — this module IS the clock; the ban points here.
    def utc_now, do: DateTime.utc_now()
  end
end
