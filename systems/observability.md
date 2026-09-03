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

## Standing decisions

- **Backends live outside the envelope** — the system that reports
  failures must not share a failure domain with the system it
  reports on (v5 §2.11). The app's contract is `/metrics`,
  structured stdout, `/health`; where those land is ops config.

  **A bounded, volatile in-process buffer of the app's own last N
  failures is not a backend, and this rule does not reach it**
  (ORC-218; the same carve-out is in `docs/v5-design-decisions.md`
  §2.11, since that section states the rule this bullet restates).
  A backend is durable and reached off-host — Prometheus, Loki, a
  future tower provider — and sharing this instance's failure domain
  with one of those is the actual hazard the rule guards against: an
  outage that takes the app down also takes its own metrics/log
  shipping down, so the record of the outage has to live somewhere
  else. A buffer that stores nothing past a restart and answers no
  request from outside this instance shares no domain with anything,
  because it isn't reporting to a second system at all — it's the
  first system holding its own recent failures long enough for its
  own operator to read them before they're gone. `systems
  /foundation.md`'s ORC-218 entry is the concrete mechanism: what
  the buffer holds, how it's fed, and the route that reads it back.
  Bound and mechanism live there because the code does — `lib/catapult
  /foundation/**`, not a shared component — and this bullet is what
  stops that read from looking like a quiet reversal of the rule
  above it.

  **The tower-based error reporting this doc's own opening paragraph
  names feeds the same buffer rather than opening a second one**
  (v5 §2.11's "error tracking via tower... as one more adapter"). One
  crash is one occurrence: when tower's own provider-adapter hook
  lands, it attaches to the identical `[:phoenix, :error_rendered]`
  telemetry event `systems/foundation.md`'s ORC-218 entry already
  reads, forwarding to a durable, off-host backend — exactly the shape
  "backends live outside the envelope" asks for — rather than a second,
  independently-written capture path that could disagree with the
  buffer about what happened.
- **Instrumentation comes from the substrate's macro, not from this
  component** — this component consumes the registries and spans;
  it never asks app code to instrument itself.
- **Content never enters the operational channel by default**; the
  content channel is declared, retention-bounded, and
  redaction-filtered by a project-supplied policy.
- **The plane is the first consumer**: pipeline health (Blocked
  ages, stale claims, mutex-wait per label, deploy timeouts) ships
  as metrics from day one of delivery — closing orchestration's
  "no alerting anywhere" open item as a side effect.
- **The mailbox guardrail is sampled here, because the VM has no
  enforcement to offer** (ORC-21). `processes/0`'s heap guardrail is a
  BEAM process flag and stays substrate's; the message-queue half has
  no per-process flag at all, and the VM's only queue facility —
  `:erlang.system_monitor/2`'s `long_message_queue` — is node-global,
  notify-only, and singular, so any library setting a system monitor
  silently replaces ours (`systems/substrate.md` records the
  verification). A declared threshold sampled per registered process
  and emitted as telemetry is what is actually on offer, and this
  component is where it belongs by the rule directly above: substrate
  declares, this component consumes the registries. Sampling also
  survives what a monitor does not — several samplers coexist, and a
  reading nobody clobbers is the difference between a signal and a
  guardrail that reports clean because something else armed first.

  **A full mailbox is reported, never killed.** The heap bound kills
  because a process that will not stop allocating takes the node with
  it; a process that is merely behind is usually the only thing holding
  the work, and killing it discards the queue that was the evidence.
  The declaration's name carries this — `message_queue_alarm_len:`,
  not `max_` — so the grade is legible where it is declared rather than
  only here.

## Initial vs target

Initial (spread: logging + PromEx basics land with Phase 1's macro;
this component assembles them properly ~Phase 4, when the plane has
something worth watching). Target: dashboard provisioning, provider
adapters, OTLP exporter as a later adapter.

## Depends on

substrate (registries, macro, health).
