---
paths:
  - components/substrate/**
  - lib/mix/tasks/catapult.audit.ex
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

## Initial vs target

Initial (Phase 1): behaviour + registries, export macro
(telemetry-only), audit v0, health, clock, seeds. Target: permission
enforcement wired to identity's principal behaviour; the full check
registry; published on the release train.

## Depends on

Nothing in this repo (it is the bottom). Vapor, Boundary, PromEx as
library deps.
