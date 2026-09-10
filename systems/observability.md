---
paths:
  - components/observability/**
---

# observability

The observability shared component (v5 §2.11): PromEx-based metrics
with per-component Grafana dashboards provisioned from the telemetry
registries, structured JSON logging with the operational/content
channel split and declared retention, trace-context threading through
the platform's enqueue/broadcast wrappers, tower-based error
reporting behind provider adapters, and the reference
docker-compose (Prometheus + Grafana + Loki) documented to run
outside the deployment envelope.

## #1 Standing decisions

- **#2 Backends live outside the envelope** — the system that reports
  failures must not share a failure domain with the system it
  reports on (v5 §2.11). The app's contract is `/metrics`,
  structured stdout, `/health`; where those land is ops config.
- **#3 A bounded, volatile in-process buffer of the app's own last N
  failures is not a backend, and this rule does not reach it** (ORC-218;
  the same carve-out is in `docs/v5-design-decisions.md` §2.11, since that
  section states the rule this bullet restates). A backend is durable and
  reached off-host — Prometheus, Loki, a future tower provider — and
  sharing this instance's failure domain with one of those is the actual
  hazard the rule guards against: an outage that takes the app down also
  takes its own metrics/log shipping down, so the record of the outage has
  to live somewhere else.
- **#4 The tower-based error reporting this doc's own opening paragraph
  names feeds off the same events rather than opening a second capture
  path** (v5 §2.11's "error tracking via tower... as one more adapter").
  One crash is one occurrence: when tower's own provider-adapter hook
  lands, it attaches to the identical `[:phoenix, :endpoint, :stop]` and
  `[:phoenix, :error_rendered]` events `systems/foundation.md`'s ORC-218
  entry already reads — both, not `:error_rendered` alone, for the same
  reason that entry gives: a 5xx that never raises never reaches
  `:error_rendered`, and an off-host backend missing exactly the failures
  that don't raise would be a worse gap than the in-process buffer ever
  had — forwarding to a durable, off-host backend, exactly the shape
  "backends live outside the envelope" asks for, rather than a second,
  independently-written capture path that could disagree with the buffer
  about what happened.
- **#5 Instrumentation comes from the substrate's macro, not from this
  component** — this component consumes the registries and spans;
  it never asks app code to instrument itself.
- **#6 Content never enters the operational channel by default**; the
  content channel is declared, retention-bounded, and
  redaction-filtered by a project-supplied policy.
- **#7 The plane is the first consumer**: pipeline health (Blocked
  ages, stale claims, mutex-wait per label, deploy timeouts) ships
  as metrics from day one of delivery — closing orchestration's
  "no alerting anywhere" open item as a side effect.
- **#8 The mailbox guardrail is sampled here, because the VM has no
  enforcement to offer** (ORC-21).
- **#9 A full mailbox is reported, never killed.** The heap bound kills
  because a process that will not stop allocating takes the node with it;
  a process that is merely behind is usually the only thing holding the
  work, and killing it discards the queue that was the evidence. The
  declaration's name carries this — `message_queue_alarm_len:`, not `max_`
  — so the grade is legible where it is declared rather than only here.

## #10 Initial vs target

Initial (spread: logging + PromEx basics land with Phase 1's macro;
this component assembles them properly ~Phase 4, when the plane has
something worth watching). Target: dashboard provisioning, provider
adapters, OTLP exporter as a later adapter.

## #11 Depends on

substrate (registries, macro, health).
