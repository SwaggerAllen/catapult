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

## Initial vs target

Initial (spread: logging + PromEx basics land with Phase 1's macro;
this component assembles them properly ~Phase 4, when the plane has
something worth watching). Target: dashboard provisioning, provider
adapters, OTLP exporter as a later adapter.

## Depends on

substrate (registries, macro, health).
