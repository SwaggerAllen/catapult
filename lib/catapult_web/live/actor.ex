defmodule CatapultWeb.Live.Actor do
  @moduledoc """
  The `actor_id` every write dispatched from this system's screens
  carries (`ApproveGate`, `DeclineGate`, `ResumeFlow`, `PostComment`).

  No identity component exists yet (Phase 7, v5 §7.16) and Phase 4 has
  exactly one author, so every gate action is shown to every viewer and
  every write is attributed to that one author — the same degenerate
  rendering `systems/dashboard.md`'s own ORC-114 entry records for
  `my-queue`'s tabs and `ticket`'s gate-action visibility. This is the
  one place that attribution is decided, so a later pass wiring real
  sessions has one call site to change rather than one per screen.
  """

  @doc "The current actor. Phase 4: the one author, always."
  @spec id() :: String.t()
  def id, do: "author"
end
