defmodule Catapult.Clock do
  @moduledoc """
  The injected clock (conventions §9): reading the wall clock directly is
  banned in domain code by the audit's grep — which is why this text does
  not spell the call it forbids; domain code takes the clock as a
  dependency so tests are deterministic. `Catapult.Clock.System` is the
  runtime implementation, and the one sanctioned exception.
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
