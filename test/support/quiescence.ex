defmodule Catapult.Generation.Quiescence do
  @moduledoc """
  The pure decision core of the live suite's quiescence poll
  (`Catapult.Generation.ToySeedChainLiveTest`, `systems/generation.md`'s
  ORC-225 entry): given one poll's run set and the loop's own prior
  state, whether the quiet window just opened, is still open, or never
  started (`next_quiet_since/5`); given that state plus a deadline,
  whether the loop should stop — quiescent or timed out — or continue
  polling (`outcome/4`). No network, no `Process.sleep`, no
  `ExUnit.Case` — the live test itself owns all three; this module
  owns only the arithmetic design review spent three rounds hardening,
  so it can be exercised with synthetic run-list inputs
  (`test/catapult/generation/quiescence_test.exs`) rather than only by
  a live run against a remote instance.

  Lives in `test/support/**` (foundation's) rather than `lib/`: this
  logic exists only to drive a live test's own polling loop and has no
  runtime caller (`Catapult.ToySeed`'s own moduledoc draws the same
  line, for the same reason).
  """

  @doc """
  Whether the observed run set is quiet right now, and since when.
  `runs`/`ids` are this poll's own; `prev_ids`/`quiet_since` are the
  prior poll's state (`nil` before any quiet window has opened). An
  empty run set is never quiet, however it compares to `prev_ids` — a
  bare "the id set is stable" check is vacuously true on a project the
  sweeper hasn't reached yet, which is exactly the bug this guards
  against (`systems/generation.md`'s ORC-225 entry).
  """
  @spec next_quiet_since([map()], MapSet.t(), MapSet.t() | nil, integer() | nil, integer()) ::
          integer() | nil
  def next_quiet_since(runs, ids, prev_ids, quiet_since, now) do
    terminal? = runs != [] and Enum.all?(runs, &(&1["status"] in ["completed", "failed"]))
    stable? = runs != [] and ids == prev_ids and terminal?

    cond do
      stable? and quiet_since -> quiet_since
      stable? -> now
      true -> nil
    end
  end

  @doc """
  Whether a loop holding `quiet_since` at `now`, against `deadline`
  and `quiescence_window`, should report the run set quiescent, time
  out, or poll again. Quiescence is checked before the deadline, so a
  quiet window that has already stood open long enough wins even on a
  poll made at or past `deadline`.
  """
  @spec outcome(integer() | nil, integer(), integer(), integer()) ::
          :quiescent | :timeout | :continue
  def outcome(quiet_since, now, deadline, quiescence_window) do
    cond do
      quiet_since && now - quiet_since >= quiescence_window -> :quiescent
      now >= deadline -> :timeout
      true -> :continue
    end
  end
end
