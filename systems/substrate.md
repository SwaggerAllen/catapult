---
paths:
  - components/substrate/**
---

# substrate

The elixir-target platform substrate: everything a Catapult-built app
(and Catapult itself) adopts to honor the convention corpus. Shipped
as a hex package via the registry; Catapult consumes it as a path dep
— the plane is its first consumer.

## Owns

The component behaviour (`use Catapult.Component`) and its registry
callbacks (config/Vapor with secret flags, pubsub topics, Oban
queues with cron annotations, telemetry events, `events/0`,
`processes/0`, seeds, `errors/0` — boundary failure vocabulary with
remedies, `externals/0` — wrapped third-party services; v5 §2.2);
the compile-time root composer with collision checks; the boundary-export macro (telemetry
spans now, `@requires_permission` enforcement when identity lands);
`mix catapult.audit` and its check registry; the health-endpoint
plug (SHA + per-component readiness); the injected clock behaviour;
the seeds release task.

## Standing decisions

- **One macro layer, two concerns.** Telemetry instrumentation and
  permission enforcement ride the same boundary-export macro —
  built once, because both need the same interception point and two
  macro layers on one function is a composition bug farm.
- **The audit is a check registry, not a monolith.** Platform
  extensions (v5 §9) register checks; the ES family registers the
  purity floor, delivery registers file-map checks. Rationale: the
  audit grows for the life of the platform; a registry grows by
  entries, a monolith by merge conflicts.
- **Registries fail the build on collision, never warn.** A warning
  about a name collision is a collision that ships.
- **The gate set is a property of a mix project, not of the repo.**
  The audit's greps are `Path.wildcard("lib/**/*.ex")`, rooted at the
  working directory — deliberately, because this task ships into
  every generated project and the shape of *this* tree is not a fact
  it may know. The consequence is the rule: every mix project in the
  repo runs the whole conventions §2 set in its own directory, and
  adding a mix project means adding its gate block. Widening the
  glob instead is ruled out in `docs/non-goals.md`. In the substrate
  the greps are the entire value of the run — it declares no
  components, so the composer check validates an empty list and the
  audit is exactly its two greps there.
- **`catapult:allow` is same-line, and marks code, never prose.** The
  check reads the tag off the matching line only; a comment on the
  line above is not an escape, however plainly it is written. Kept
  same-line because any other span asks each reader to work out how
  far a given escape reaches, and an escape whose extent is
  arguable is worse than none. Documentation that names a banned construct is reworded, not
  tagged: an allow tag asserts "this occurrence is a deliberate
  exception", and spending it on a sentence *about* the ban degrades
  the one signal review has, in a package whose docs get published.
  The cost is real and accepted — the clock's moduledoc and the
  audit's own cannot spell the construct they forbid.
- **The substrate audits its own lockfile.** `mix deps.audit` reads
  the lock of the project it runs in, so `components/substrate/mix.lock`
  is checked by nothing today; the root run covers the root lock
  only. That the two locks currently name the same eight versions is
  a coincidence of resolution, not an enforced property —
  `--check-locked` holds a lock against its own `mix.exs` and says
  nothing about the other lock. A coincidence is not a gate, so the
  substrate declares `mix_audit` itself.

## Initial vs target

Initial (Phase 1): behaviour + registries, export macro
(telemetry-only), audit v0, health, clock, seeds. Target: permission
enforcement wired to identity's principal behaviour; the full check
registry; published on the release train.

## Depends on

Nothing in this repo (it is the bottom). Vapor, Boundary, PromEx as
library deps. `mix_audit` dev/test-only and `runtime: false`, per the
lockfile decision above — BSD-3-Clause, so it neither troubles the
Apache-2.0 split nor reaches a hex consumer, who never fetches it.
