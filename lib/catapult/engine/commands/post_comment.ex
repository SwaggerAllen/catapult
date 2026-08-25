defmodule Catapult.Engine.Commands.PostComment do
  @moduledoc """
  Records a human review comment against a node's currently committed
  body (v5 §7.4, `systems/engine.md`'s ORC-34 design pass). Aggregate
  id: `project_id`.

  `body_sha` names the committed draft the comment was read against;
  the aggregate rejects a stale one rather than silently attaching the
  comment to whatever is current by the time the command lands
  (`systems/delivery.md`'s point-of-action rule). `locator` is
  nullable — always `nil` until `docs/ui-spec.md` §5's v2 per-sentence
  anchoring ships. `posted_at` is caller-supplied, per this system's
  own purity floor: never generated inside the aggregate.

  No `kind`/`author_kind` field: nothing posts a machine comment
  through this command in Phase 4 (the chain's own auto-review is
  `WriteReview`, a distinct record with its own `kind`), so this stays
  human-authored by construction.
  """

  @enforce_keys [:project_id, :node_id, :body_sha, :author_id, :body, :posted_at]
  defstruct [
    :project_id,
    :node_id,
    :body_sha,
    :locator,
    :author_id,
    :body,
    :posted_at
  ]
end
