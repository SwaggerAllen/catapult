defmodule Catapult.Clock do
  @moduledoc """
  The injected clock (conventions §9): `DateTime.utc_now/0` and
  `NaiveDateTime.utc_now/0` are banned in domain code
  (`Catapult.Audit.Checks.WallClock`), which takes the clock as a
  dependency instead so tests are deterministic.

  This text used to avoid naming the call it forbids, because the check
  was a grep and would have matched itself. It is an AST check now, so a
  string is a string — the ban's own documentation being unable to state
  the ban was the clearest cost of the old grade, and it is the first
  thing the new one pays back.

  `Catapult.Clock.System` is the runtime implementation, and the one
  sanctioned exception.
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
