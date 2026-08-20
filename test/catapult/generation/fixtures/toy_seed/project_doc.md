# Signpost — project doc

Signpost is an internal link-shortening service. Two jobs: turn a long
URL into a short code, and turn a short code back into a redirect —
fast, because the redirect path is the one on the request hot path for
every other internal tool that links through it.

## Why this exists

Teams keep pasting long, ugly internal URLs into chat and docs. A
short code (`sp.internal/abc123`) is stable even when the thing it
points at moves, and click counts tell a team whether a shared link is
actually used.

## Shape

- **Redirecting** a short code to its target is the hot path: one
  lookup, one 302, every time. It has to survive the target service
  being down (the redirect still has to work) and it counts the click
  on the way through.
- **Creating and administering** links is the cold path: validate the
  target URL, mint a short code, let an owner retire a link later.
  Lower volume, can afford to be slower and stricter.

## Toy scope

This is a seed for the pipeline's own toy-project chain test — read
in one sitting, not a spec for a real service. It exists to give every
tier in the default bundle something small and concrete to generate
against.
