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

## #1 What it reads

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

## #2 Filters, and what they resolve to

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
filtering already-materialized fields, not a new stored index or a second read path.

## #3 The version, always

**The read path is where upcasting happens, and this screen is built around that fact rather than
around hiding it.**

So every event row carries **both** version facts, not one: the version it was recorded at
(`events/0`'s own `{type, version}` pair for the stored event) and the version its rendered
payload reflects (always the current one, since that is all the read API returns). When they
match, one badge. When they don't, both — recorded version, then an arrow to current, on the row
and again on the open detail pane, so scanning the list and reading one event both carry the fact.

**No raw, pre-upcast payload view.**

## #4 Empty is a real state

A project with no events yet is `{:error, :stream_not_found}` from the store, not a degenerate
case of a populated list — render it as "nothing has happened here yet," not as a loading state or
an error banner.

## #5 Non-goals

- Replay-to-sequence (rebuilding projections as of an earlier event) is a different, heavier
  operation named separately in `docs/ui-spec.md` §3.3 and staged later.
- No write affordance of any kind. This is a read of the log; the log has no UI-initiated writes,
  here or anywhere in this system (`systems/dashboard.md`'s standing "reads projections only").
