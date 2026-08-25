---
paths:
  - storybook/screens/event_log/component.ex
  - storybook/screens/event_log/component.story.exs
---

# event-log

Inspection of one project's event log (`docs/ui-spec.md` §3.3): what happened, in what order,
and — for anything old enough to have changed shape — which shape you are looking at. Not
replay-to-sequence, dispatch history or run transcripts; those are named in the same ui-spec
bullet and are later stages (`systems/dashboard.md`'s Initial-vs-target).

## What it reads

One project, one stream. Engine's aggregate is per-project (`systems/engine.md`, "a project has
one aggregate, not two"), and delivery's feature-ticket lifecycle and container lifecycle write
onto that same aggregate rather than a second one (`systems/delivery.md`) — so a project's whole
history, node lifecycle and container/queue/flag events alike, is one ordered log reachable
through `Commanded.EventStore.stream_forward/3` against `Catapult.Engine.Application`. There is
no `Engine.Store` read path for this: `Store` is the *projections* subcomponent, and the log is
a different fact, reached the way `Catapult.Engine.Projections.RunFailures` already reaches it —
through the event store's own read API, never a materialized table standing in for it.

**Every read here is project-scoped, and the route carries the project (ORC-87).** A node id is
a per-project slug, not globally unique, and neither is a stream. There is no cross-project or
"all projects" view: pick a project first, always.

## Filters, and what they resolve to

`docs/ui-spec.md`'s event-log bullet names three filters — stream, ticket, actor — and this
section is the concrete binding, since none of the three is a field the log's events carry under
those names:

- **stream** is the project itself. One project is one stream (`project-<project_id>`), so
  choosing a project *is* the stream filter; there is nothing narrower to pick within it.
- **ticket** matches `container_id`. Containers are the plane's own state for projects,
  milestones and their queues (ORC-104, ORC-105) and the feature-ticket lifecycle's projected
  unit (ORC-32) — every container, queue, finding-adjudication and flag event carries one.
- **actor** matches `actor_id`, where the event carries one. Not every event does — a
  generation-tier draft commit is the executor's own act, not a human's or an external system's,
  and has none. Filtering by actor silently excludes actor-less events rather than erroring; that
  is not a bug in the filter, it is what "no actor" means.

**A free-text node match is a fourth, unnamed filter, deliberately not elevated to the other
three's status.** `explain-why` links here with a node id so an operator can go straight from "what
is blocking this" to "what happened to it" (the ticket's own "enough navigation to get from a
stalled feature to the log entries that explain it"). It is implemented as a match against event
payload fields that already carry a node id (`node_id`, or a draft/review id resolvable to one) —
filtering already-materialized fields, not a new stored index or a second read path. It is not
named in `docs/ui-spec.md` because it answers a narrower question than the other three: "everything
about this one node," not "everything of this kind."

## The version, always

**The read path is where upcasting happens, and this screen is built around that fact rather than
around hiding it.** `Commanded.EventStore.stream_forward/3` returns the *current* struct for every
event, never the originally-stored one — `{:review_written, 1}` and `{:review_written, 2}` are a
live pair (`lib/catapult/engine/events.ex`) with a real upcaster behind them, and a v1 event read
today comes back as a `ReviewWritten` v2 struct: `score` already multiplied onto the 0-100 scale,
`kind` already defaulted to `:ai`. An inspector that renders that payload with no version marker is
telling the operator the log always looked like this, which is false and is exactly the lie
`explain/2`'s own moduledoc warns an inspector must not tell.

So every event row carries **both** version facts, not one: the version it was recorded at
(`events/0`'s own `{type, version}` pair for the stored event) and the version its rendered
payload reflects (always the current one, since that is all the read API returns). When they
match, one badge. When they don't, both — recorded version, then an arrow to current, on the row
and again on the open detail pane, so scanning the list and reading one event both carry the fact.

**No raw, pre-upcast payload view.** The temptation, once the disclosure above exists, is to go
one step further and show what was actually serialized — the literal `0.73` before it became `73`.
Refused: the only way there is a read path that bypasses `Commanded.Event.Upcaster`, which means
this screen reaching around the store's own API rather than through it (v5 §2.4, "reached only
through their APIs"), for a fact that changes nothing about what replay will do. The recorded
version number is the honest answer to "was this upcast," and it is what `events/0`'s registry
already makes a first-class fact — the payload underneath does not need to be reconstructed to
prove it.

## Empty is a real state

A project with no events yet is `{:error, :stream_not_found}` from the store, not a degenerate
case of a populated list — render it as "nothing has happened here yet," not as a loading state or
an error banner.

## Non-goals

- Replay-to-sequence (rebuilding projections as of an earlier event) is a different, heavier
  operation named separately in `docs/ui-spec.md` §3.3 and staged later.
- No write affordance of any kind. This is a read of the log; the log has no UI-initiated writes,
  here or anywhere in this system (`systems/dashboard.md`'s standing "reads projections only").
