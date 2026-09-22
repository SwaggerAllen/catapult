# Catapult

**Designing and delivering software too large to hold in context.**

Catapult keeps a project's entire design as a **dynamic document graph** — typed, addressable
nodes describing the system at progressively finer grain, declared in a small YAML DSL and
reactive to change. Edit a node, or change the schema a tier is written against, and the graph
works out what has gone stale and regenerates only that. Each stage reasons over a compressed
slice of its parents rather than the whole system, which is what makes a project larger than a
context window tractable at all.

The design process runs end to end on its own, behind checkpoints you configure: any tier can be
gated on human review, agent review, or neither. Once a design is approved, the same graph drives
delivery — tickets minted per scope, agents dispatched to implement them, and what they built
reconciled against what was approved.

> **Status: in active development.** Expect ongoing breaking changes and bugs; not all
> functionality has been proven. `docs/build-plan.md` carries the current phase and what is still
> outstanding. This repository is open because the design record is worth reading, not because
> the system is ready to use.

## Why a graph

Two problems converge on the same answer.

**Context.** A system of any size does not fit in a model's window, and summarizing it away loses
exactly the interface details that matter. A graph lets each generation step take a compressed,
typed view of its parents — names, roles, API intents, public surfaces — instead of the prose
that produced them.

**Technical debt.** Debt is usually described as a discipline problem. It isn't. Located
properly, the mechanism is **contract renegotiation**: systems ship feature by feature, so
interfaces get renegotiated per feature, abstractions leak, and nobody re-reviews the whole.
Human teams absorb this for years. AI-delivered projects hit the same failure class within weeks,
because the rate of change goes up and the reviewer holding the system in their head goes away.

If that's the mechanism, the cure isn't better review. It's to architect the end state once, then
hold the contracts structurally. A graph can do that; a chat log cannot.

Target: single authors and small teams shipping enterprise-scale systems.

## The design side

The chain runs from input documents through a product definition (UX, information architecture,
journeys, screens) into an architecture chain — `vocab` → `sysarch` → `comparch` → `subcomparch`
→ `impl`, alongside frontend and screen-collection families.

- **The DSL is small and has a grammar.** YAML bundles declare tiers, edges, schemas, flows and
  prompts, with a separate workflow axis for ticket types, gates and environments. Normative
  grammar documentation lives in `docs/dsl/`, with a worked example and a checker.
- **Generation is reactive, not scheduled.** The graph is an event log; `ready_scopes` — what is
  eligible to generate next — is a projection that enqueues work rather than a queue anything
  polls. Readiness is derived state, so it cannot drift from the graph it describes.
- **Every artifact is schema-validated at commit**, and review is a gate rather than a
  suggestion. A declined review threads back into regeneration as feedback instead of starting
  over.
- **Gating is configurable per tier.** Human review where judgment is needed, agent review where
  it isn't, and neither where the schema already says enough.

## The delivery side

The premise is that the most reliable way to get good output from a model is programmatic
guardrails, not better prompting. So the graph isn't only a design record — it's the enforcement
surface for the code that comes out of it.

- **Architectural decisions become machine-checkable.** What the design says about boundaries,
  ownership and public surfaces is checked against the delivered code, rather than being prose
  nobody rereads.
- **Policy nodes attach guardrails at the level an invariant actually lives** — some belong to a
  component, some to a subsystem, some to the whole project — so enforcement sits where the rule
  does.
- **Generated projects inherit an opinionated architecture** rather than starting from an empty
  `mix new` — see [The substrate](#the-substrate) below.
- **`mix catapult.audit` enforces what a style guide can't.** An AST-parsing Mix task that fails
  the build on declared-but-unused error kinds, unapplied VM guardrails, wall-clock calls in
  domain code, unwrapped secrets in logs, boundary violations and license-split violations.
  Escapes are explicit `# catapult:allow` comments, and an escape covering nothing is itself
  reported.
- **Agentic review covers the rest.** Opinions that can't be expressed as a test or a macro get
  an agent pass instead of being left to hope.

## The substrate

A generated project doesn't start from a blank slate. It links a convention corpus that ships as
its own Apache-2.0 library, and inherits a shape rather than a style guide.

- **Components declare a behaviour and register themselves.** Name collisions are caught at boot
  and again by the audit, so two components can't quietly claim the same role.
- **`defexport` declares a component's public surface** and wraps each exported function in a
  telemetry span at compile time — so the export list the API-drift audit checks against is the
  same one that produces the instrumentation.
- **Boundaries are declared, not conventional.** The `boundary` compiler flags calls that cross
  one, and CI runs warnings-as-errors, so a flagged call fails the build.
- **The clock is injected.** Time is a dependency, so it's testable — and a wall-clock call in
  domain code fails the build.
- **Secrets are wrapped types**, not strings, so logging one by accident isn't possible rather
  than merely discouraged.
- **Tables have a single owner.** No two components write the same table.
- **Each component's total public API is frozen**, with a drift audit that fails when the surface
  changes without the change being declared.
- **Tests don't touch the network.** Enforced, not requested.
- **The audit ships with the substrate**, so these rules hold in the generated project's own CI,
  not only in Catapult's.

The list looks like taste, and it isn't. Each item exists because it converts a specific class of
agent mistake — the reused name, the boundary quietly bypassed, the secret in a log line, the
test that passes only when a third party is up — from something a reviewer has to catch into
something the compiler or the build catches. That's what "AI-centered architecture" means here in
practice.

## What's built

~207 Elixir modules across two Mix projects — the plane and the separately licensed substrate —
each with its own full gate suite.

| Area | State |
| --- | --- |
| `core.dsl` | Bundle loader, core vocabulary, extension registry, type-level acyclicity validation, path-escape guard on bundle-relative content paths |
| `core.engine` | Aggregate, router, commands and events, reducer, projections, reactive scheduler and sweeper, EventStore-backed log |
| `generation` | Context assembly, Liquid rendering, dispatch worker, commit path, schema validation at commit, regeneration-with-feedback |
| `delivery` | Feature and container lifecycles as process managers, host port with an in-memory fake, GitHub Actions OIDC verification for dispatched runs, decline harvesting from PR review into regeneration feedback |
| Dashboard | LiveView: queue, board, ticket, sentence-granularity document review, event-log inspection, and an `explain-why` screen answering what is blocking a scope. **Unreliable; under active work.** |
| Default bundle | 21 XSD schemas, ~18 Liquid prompts plus review prompts and partials, six edge families, five plan flows |

CI enforces the whole gate set on both projects: format, Credo strict, Sobelow,
warnings-as-errors, the boundary compiler, xref cycles at zero, a compile-connected ratchet at
zero, the custom audit, dependency auditing, and the test suite.

**Not built yet, deliberately, with phases attached:** identity (7), the LLM adapter component
(8 — the plane's own chain never uses it), registry-as-service, the React/TypeScript client
corpus (7), the prompt-evaluation harness (6), full observability. See `docs/build-plan.md` and
`docs/non-goals.md`, where non-goals are first-class and audited.

## How this repo gets built

Catapult does not build itself — self-bootstrapping was explicitly descoped and argued away. It's
delivered by **[orchestration](https://github.com/SwaggerAllen/orchestration)**, a Go pipeline
built for the purpose: one agent designs against review, another implements, a third reconciles
what was built against what was approved, and a fourth reviews at milestone boundaries for
accumulated tech debt. 72 tickets are archived across six milestone retrospectives
(`docs/retros/`), with roughly fifteen more since.

The acceptance test for the whole thing, at phase 8, is a real prior application rebuilt end to
end from its documentation alone, delivered by Catapult.

## Reference instance

One deployment runs as the reference instance: the control plane running against its own
repository on DigitalOcean App Platform. It isn't a demo — it's the plane that works this repo's
tickets, so the pipeline's deploy step is checking a real running system. `GET /health` is the
contract everything else reads, returning the build's git SHA, an overall `ok`, and per-component
readiness as JSON. `/dispatch/*` serves the agent-dispatch host port's context-fetch and
result-report calls. Instance specifics live in `SETUP.md` §2.

## Licensing

Two kinds of code with opposite needs. The plane is **AGPL-3.0-only**: network-facing software
where plain GPL would impose nothing. Everything that ships into a generated project —
`components/**` and `bundles/**` — is **Apache-2.0**, because generated applications link the
substrate and receive template content verbatim, and copyleft there would propagate into every
downstream application. The split is enforced by the audit. Full policy in
[LICENSING.md](LICENSING.md).

## Further reading

- **[orchestration](https://github.com/SwaggerAllen/orchestration)** — the pipeline that delivers
  this repo.
- **[Polyphony](https://github.com/SwaggerAllen/polyphony)** — an event-sourced narrative engine
  built alongside this work.
- **[SiegeEngine](https://github.com/SwaggerAllen/SiegeEngine)** — the predecessor that
  established the tier chain, superseded by this.
- **[Trying to Build a System Bigger Than Claude Can Hold](https://strutco.substack.com/p/trying-to-build-a-system-bigger-than)**
  — the argument, written up.
