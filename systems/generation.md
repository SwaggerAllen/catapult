---
paths:
  - lib/catapult/generation/**
  - test/catapult/generation/**
---

# generation

The plane's design-dialect coordination — **agents end-to-end (v5
§1.2): the plane never generates, it dispatches**. This system takes
ready `(tier, scope)` pairs from `ready_scopes`, evaluates context
walks and renders the Liquid prompt, dispatches an agent run via the
delivery system's host port, serves the rendered context to the
runner-side harness, and validates the committed body against the
tier's grammar (via core_dsl) when the agent reports. The app-facing
runtime dialect (components/runtime, Phase 8) shares the rendering
and validation logic and must not fork it.

## Standing decisions

- **The plane holds no working copies and makes no model calls.**
  The runner's checkout is the working copy; bodies reach the plane
  as commits to read at a SHA, never as files on its disk. The
  in-plane persistence class (branch management, working trees,
  ephemeral-disk writes) is deleted by construction.
- **Dispatch coordination holds no state and makes no decisions**:
  what to generate comes from `ready_scopes`; what to render comes
  from the bundle; whether output is acceptable comes from the
  grammar. If coordination needs memory, the design is wrong
  somewhere upstream.
- **Validation failure is feedback, not error** (v4 §A.1.3 carried
  forward): a grammar-invalid commit returns a typed error the agent
  retries with, bounded; a half-committed state is impossible
  because commit-time validation gates the event.
- **Same renderer for generation and review** (the per-tier triad
  invariant, SiegeEngine's rule): the reviewer sees exactly the
  generator's context plus the draft. Enforced by sharing the
  context-assembly code path, not by convention.
- **Latency scales the pool, never the architecture**: slow
  generation means an autoscaling worker pool pulling from the
  queue — generation never moves in-plane.
- **The execution substrate is an adapter behind the host port**
  (v5 §7.12.1, §8): Actions (the default) and the worker pool (BYO
  cluster canonically, managed opt-in) are two adapters over one
  runner-harness contract — fetch rendered context, run agent,
  commit, report. The contract is the invariant; nothing outside
  the Actions adapter may assume Actions. The dispatch-concurrency
  cap is a per-instance `tunable` in plane state, never a config
  constant — scheduler backpressure and hosted tiering share it. A
  **daily dispatch budget** (warn + cutoff `tunable`s) rides beside
  it; alerts via observability, mirrored on the dashboard (v5 §7.4's
  two-channel rule).
- **Runners authenticate with GitHub Actions OIDC** (v5 §7.12.1):
  the plane's context-fetch and result-report endpoints accept
  GitHub's signed ID token, validated against GitHub's JWKS with
  audience + `repository` + `run_id` matched to the plane's own
  dispatch record. No secret rides the dispatch inputs (they are
  visible-log territory). Pool adapter: plane-minted per-dispatch
  tokens over the dispatch channel. **Rendered context never
  contains bindings or credentials.**
- **The endpoint's listener is foundation's, not a second one this
  system stands up** (design review finding, ORC-9): `systems
  /foundation.md` records where context-fetch and result-report are
  actually served — a second path on the existing health listener,
  composed from generation's and delivery's `api_surface/0`
  declarations, ahead of the general router that will eventually
  absorb them — and why it isn't dashboard's router yet. This ticket
  carries `system:foundation` alongside `system:generation` and
  `system:delivery` for exactly that reason: the handler logic (OIDC
  validation, run correlation, context/result payloads) stays here and
  in delivery's file map; foundation owns only the listener it answers
  on.
- **Run-result reporting is that same authenticated callback, not a
  marker comment** (ORC-9's open question, resolved): the
  result-report call reuses the identical OIDC bearer settled in the
  bullet above — no second trust decision. The deciding reason is the
  retry promise below: a grammar-invalid commit returns a typed error
  the agent retries with, *bounded within the same run* — and only a
  synchronous request/response can hand that back to a process still
  executing. A marker comment can announce a result to a human later;
  it cannot hand a typed validation error to the agent that is still
  running. Marker comments stay the right shape exactly where
  `systems/delivery.md` keeps them — GitHub PR comments, a surface
  whose cadence the plane doesn't own — but a result report is
  plane-to-plane over a channel the plane owns both ends of, so the
  marker's reason for existing doesn't transfer here.
- **The runner harness is orchestration's, consumed as a pinned
  dependency — not a second implementation in this repo** (ORC-9's
  other open question). The shape v5 §7.12.1 asks for — invoke the
  agent with a model-credential pair, catch failure, fail over on
  limit-class errors only — is not a new problem: it is the harness
  already running every Catapult ticket, including this one. A
  repo-local copy (a composite action in `.github/`, a script in
  `bundles/platform-elixir`) would duplicate exactly the logic v5
  §1.2's third reason already refused to duplicate ("one execution
  path... extended rather than duplicated"), and `docs/non-goals.md`'s
  no-self-bootstrap entry ("Catapult consumes the shared components as
  an ordinary library user") states the same preference one layer up.
  Named consequence rather than a discovered one: today's shipped
  harness fails over on any non-zero exit and string-matches another
  tool's stderr to say why, which cannot honor "limit-class failures
  only" — so until it exposes a structured signal (the CLI's JSON
  output mode is the candidate), the Actions adapter dispatches with
  **no failover**, enforced the only way it can be against a harness
  that fails over on any non-zero exit by itself (design review
  finding, ORC-9): **the adapter sends one credential, not the pair.**
  The bindings `tunable`'s order still exists and still decides which
  one — its first-ordered entry is the sole model-credential dispatch
  input the harness receives; the second slot is read from bindings
  same as always but withheld from the dispatch payload, so there is
  nothing for the shipped harness's blind failover to reach for even
  though it would try. A run failure therefore fails the run outright,
  which is what "no failover" actually has to mean given a harness
  that cannot be told not to. The day the harness's classification
  lands, the adapter starts sending the tunable's full ordered pair
  instead of its head — a one-line change on this system's side, not a
  new decision, because the contract (v5 §7.12.1's model-credential
  pair, order from the tunable) was already built for two; it was only
  ever the transport withholding the second slot. This is a gap to
  close upstream, not a reason to build a parallel classifier here.
- **Model credentials are a pair with limit-class failover** (v5
  §7.12.1): the runner harness accepts `ANTHROPIC_API_KEY` and/or
  `CLAUDE_CODE_OAUTH_TOKEN` — customer-side secrets the plane never
  sees. Order is a per-project bindings `tunable` passed as a
  dispatch input (a preference, not a secret); failover on
  limit-class errors only; the run report names which credential
  served.
- **The three §7.15 pause/resume invariants bind this executor, not
  aspirational**: one dispatched run per ready scope, one atomic
  commit per scope at the end, no memory across dispatches. The
  scheduler (`systems/engine.md`) already hands the third one over for
  free — `Catapult.Engine.Scheduler` broadcasts the *full* ready set on
  every trigger, holds no memory of what it last announced, and says
  so in its own moduledoc ("the payload is a hint, never an
  authority — a consumer re-validates before acting on it") — so this
  executor's own re-check at dispatch time (is this scope still ready?
  is it already committed?) is the same discipline one layer up, not
  new work. The first invariant is where dedup actually has to live:
  Oban's own job uniqueness, keyed on `{project_id, tier, scope_key}`
  and held for the scope's in-flight window, is what turns a
  liberally-re-announcing broadcast into one dispatch per scope,
  rather than a new in-plane pending-set — the exact kind of
  coordination memory the "holds no state" bullet above already
  refuses. Repeated limit-class failure on the *same* scope — as
  opposed to a failure that clears on redispatch — is `Blocked` with a
  named reason (§7.15), never a further retry: the readiness query
  cannot distinguish "will succeed next window" from "never fits in a
  window," so the executor answers that with a query, not a counter —
  **the count is derived from the log, never held** (design review
  finding, ORC-9, resolving the apparent conflict with the invariant
  just stated). Every limit-class run failure is its own event, on the
  scope's node, in generation's own `events/0` (a new entry this
  ticket adds), landing in the same per-project stream engine's
  `draft_committed` already writes to — one aggregate per project, not
  one per system. The derivation walks the log backward from now to
  the node's most recent `draft_committed` (or the log's start, if
  none), counting limit-class failure events since. `Blocked` fires
  once that count repeats past one. This satisfies the invariant
  rather than contradicting it: "no memory across dispatches" is a
  claim about the *dispatched run*, which still re-renders its context
  walk and starts clean every time — the count lives once, in the
  plane's log, the same place every other derived answer in this
  system already lives (`systems/engine.md`'s "no in-memory
  pending-set" doctrine, one layer down), not in a table row or an
  Oban attempt counter. The rejected alternative is concrete enough to
  name the reason it's wrong: an Oban attempt count is scoped to one
  job, and the uniqueness key that turns a re-announced ready scope
  into one dispatch (above) is held only for the scope's in-flight
  window — once that window closes, a redispatch is a *new* job
  starting its attempt count at zero, so the very mechanism that
  dedups dispatch would silently reset the failure count it would have
  to hold. The log has no such window.
- **ORC-87 confirmed rather than assumed, and this design carries its
  consequences forward.** The Oban uniqueness key the first §7.15
  invariant leans on, `{project_id, tier, scope_key}`, matches the
  unique index ORC-87 actually landed on `engine_nodes`
  (`(project_id, tier, scope_key)`) — `scope_key` is unique only
  within a project and a tier, exactly the granularity the dedup key
  needs and no finer than the table itself already enforces, so
  nothing about the key changes. Everything this executor commits —
  drafts, and the run-outcome events the bullet above adds — writes
  with `(project_id, id)` from the start, through `Store`'s
  post-ORC-87 shape (`get_node/2`, `edges_from/3`, `approve_node/2`
  all take `project_id` now); no new bare-id `Store` call site is
  introduced here for ORC-87 to have to find and thread later.
- **`feedback`/`prior_review`'s source is decided, not built here, and
  both reads land inside this system rather than routing through
  delivery** (ORC-34, design pass; revised on design review —
  the first draft routed both through a `Catapult.Delivery` read the
  same shape `draft_variable/2` takes for `draft`, which made sense
  only while `feedback` was delivery-owned cache state; neither read is
  delivery's any longer, so the detour is gone with it).
  `ContextAssembly.build_variables/5`'s own moduledoc marks both
  "Target, not Initial... unset here" — what fills the hole is two
  direct engine reads, exactly where this module already reads
  `ContextResolver.resolve/2` and `Store.fragments/2` for everything
  else it renders: `Engine.Projections.CommentFeedback.since_commit
  (project_id, node_id)` (`systems/engine.md`, a log fold with the
  identical shape `RunFailures.count_since_commit/2` already has, not
  a cache) for `feedback`, rendered as an ordered list of maps —
  `%{body:, locator:, author_id:, posted_at:}`, `locator` always `nil`
  in Phase 4 (`systems/engine.md`) — and `Engine.Store.reviews_for_node
  (project_id, node_id)` for `prior_review`, rendered as a map
  (`score`, `findings`, `kind`), both unconditional (unlike `draft`,
  neither is review-tier-only — `docs/dsl-syntax.md` §9/§3.3, §9 also
  carries the two rendered shapes above now, corrected in the same
  change). Both render blank via Solid's existing unset-is-empty
  behavior where nothing exists yet to read. Nothing about `build/4`'s
  own shape changes beyond two more entries in `build_variables/5`'s
  returned map, beside `"draft"`.
- **The agent-port fake is scope, not test scaffolding** (the same
  standing decision `systems/llm.md` makes for the runtime's provider
  fake, made here for the same reason): canned bodies through the real
  commit path are what let the whole chain run offline and
  deterministic in the default suite (conventions §9 — no network,
  ever), and it is what proves dispatch and validation correct
  independent of a live run ever firing. It ships with the port, like
  every other fake in this codebase, and is never treated as
  disposable relative to the Actions adapter it stands in for.

## Initial vs target

Initial (Phase 3): readiness-driven dispatch for the upstream tiers,
offline against the agent-port fake (canned bodies through the real
commit path), live against dispatched runs on Actions. The host
port's dispatch-facing slice — context-fetch, result-report, OIDC
validation, run correlation, its in-memory fake — is pulled forward
into this phase from delivery's Phase 4 (`systems/delivery.md`),
scoped to exactly what dispatch needs; the rest of the host port
(feature-lifecycle PR management, decline harvesting) still waits for
Phase 4. Target: review passes, regen-with-feedback threading,
executor-profile routing, the shared seam with the runtime dialect
kept clean.

## Depends on

engine (ready_scopes, commands), core_dsl (grammars, walks),
delivery (host port, dispatch, run correlation), foundation (serves
the dispatch-facing host port endpoint on its listener),
platform_content (the prompts).
