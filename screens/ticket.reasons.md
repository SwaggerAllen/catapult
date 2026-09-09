# ticket — reasons

The reason behind each rule in `screens/ticket.md`, keyed by the rule's id (orchestration's DESIGN §4). Read one with `pipeline reasons ticket#n` before changing the rule it belongs to.

## #1

Everything below is "what state is this in and what can I do about it" — the argument is "why does
this ticket exist," and a reviewer deciding a gate needs the second question answered in the context
of the first, not instead of it.

## #3

The controls are named here because the command they dispatch is this ticket's own — the same
`ApproveGate`/`DeclineGate` pair — and a future non-prose gate (Phase 7) would render them directly
on this screen with no new mechanism, only a different destination for the click.

This is the concrete case `docs/ui-spec.md`'s R-less prose gestures at when it says owning the
surface is what makes synchronous rejection possible at all: Linear cannot do this (v5 §7.16), and
it is worth a test asserting the conflict renders rather than the stale action silently applying or
silently failing.

## #5

It waits on `docs/build-plan.md`'s Phase 7 two-grain machinery (spawn, child lifecycle), and nothing
ahead of Phase 7 depends on it landing first.
