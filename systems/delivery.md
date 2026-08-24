---
paths:
  - lib/catapult/delivery/**
  - test/catapult/delivery/**
---

# delivery

The protocol plane: the Host and Deploy ports with real adapters
(GitHub, health-endpoint deploy detection) and in-memory fakes —
orchestration's port architecture re-expressed in Elixir — plus, over
them, the v5 §7 machinery in two stages: first the **authoring loop**
(Phase 4: feature-ticket lifecycle projection, gate states,
feature-branch PR management, decline harvesting), later the full
two-grain delivery (child lifecycle, mutex, dispatch, reconciliation,
the validation loop, escalations, milestones with the `:live`-gated
`retro` queue (ORC-105), the maintenance watcher).

**There is no Tracker port, and no tracker adapter is ever built**
(v5 §7.17). Ticket state is ours; the work surface is ours
(`docs/ui-spec.md`). The only outward-facing tracker interface is a
**mirror** — an outbound projection of top-level tickets only, for
teams reporting into a larger org's system, with no inbound write
path (`docs/non-goals.md`) — and it is a product feature, not a
dependency of the loop.

**There is no tracker cutover, because there is nothing to cut over
from.**
The reversal landed before any tracker integration was written, so
the plane never acquires one. Orchestration builds Catapult and
orchestration uses Linear; that is a different system running a
different loop, and it is unaffected by anything here. Catapult the
platform does not talk to Linear at all.

**Children spawn when the plan node names them, not at Building**
(v5 §7.10): a depth-scoped gate sitting before Building is
unclaimable unless its children exist by then. Creation is not
dispatchability — early children sit pre-queue until the parent's
design gates pass.

## Standing decisions

- **Ports with fakes, exactly like the Go pipeline** — the fake ships
  with the port; the sim-style test ring runs the whole protocol
  offline. This is the porting model (v5 §7.13): snapshot→actions
  purity maps near-1:1 onto a Commanded process manager.
- **The host port's second operation resets a bound repo's fixture
  content; it does not touch generated artifacts** (ORC-10). A bound
  repo has to carry a `workflow_dispatch` file before GitHub will
  accept a dispatch to it at all, and no role in this pipeline has a
  route to author a file inside a *different* repository — that repo
  is out of every agent's reach by construction, not by refusal. So
  the plane writes it there instead: the toy seed's per-role input
  documents and `.github/workflows/catapult-dispatch.yml` live as
  fixtures in *this* repo, reviewed like any other file, and `reset`
  overwrites the bound repo's contents from them. `HostPort` gains
  this as a second callback alongside `dispatch_run/1`, and the fake
  implements it too, so the offline chain test exercises the same
  reset path rather than a live-only mechanism — the same "fake is
  scope, not test scaffolding" rule `systems/generation.md` states for
  the dispatch call. What reset does *not* do: generated artifacts
  still land only through `Dispatch`'s result-report path into the
  plane's own store, never written to the bound repo, and reset does
  not make `input.<role>` resolve — that's intake, Phase 5, ORC-12
  (`docs/non-goals.md`'s ORC-10 entry). What it buys today is an
  author and a rebuild path for a fixture repo, not test determinism
  or seeded generation content.
- **`DELIVERY_GITHUB_TOKEN` gains `Contents: read and write`, pulled
  forward rather than newly spent** (ORC-10). Phase 4's
  feature-lifecycle PR management already needs contents-write on a
  bound repo regardless of this ticket; reset draws on that same
  grant early instead of inventing a second one. The grant is global —
  one config value, not one per project binding — so it reaches every
  bound repo the moment it's set. Acceptable for a test repo the
  author owns; not fixed here. `lib/catapult/delivery.ex`'s own config
  comment already names the GitHub App installation token as the
  shape that scopes this per-repo, and that stays the answer — ORC-10
  doesn't owe it.
- **Ticket state is a projection; the event log is the authority**
  (v5 §7.1). Unchanged by owning the tracker — if anything sharpened,
  since the surface and the authority now agree. Human actions arrive
  as commands the plane validates: on a surface we own the rejection
  lands at the point of action (§7.16's compare-and-swap); through
  Linear it degrades to validate-or-revert, because Linear applies
  last-write-wins and tells nobody. No plane behavior may depend on
  tracker state it didn't project.
- ~~**Every comment the plane relies on carries a fixed marker.**~~
  **Retired for surfaces we own** (v5 §7.17, `docs/ui-spec.md`).
  Markers existed because an external tracker had nowhere to put
  typed data, so protocol state rode in prose behind a prefix and
  counts and resumes parsed it. Owning the tracker removes the
  premise: **plane-authored annotations are records with kinds**, and
  nothing parses prose to find them. The rule survives verbatim on
  surfaces we do not own — GitHub PR comments — where the original
  reason still holds, and orchestration keeps it wholesale since it
  has no store of its own.
- **Intent → idempotent effect → observed completion** (v5 §7.1):
  no external effect shares a transaction with an event. Outbound
  acts record intent, execute via outbox workers, and complete only
  on the world's confirmation (webhook/sweep). Effect-without-record
  heals by re-observation; intent-without-effect is visible and
  escalates. The log never says "done" on the plane's own word.
- **The authoring loop is a strict subset, not a fork**: Phase 4
  ships the gate/PR/harvest slice of the same modules the full
  machinery grows into; no throwaway scaffolding that Phase 7
  rewrites.
- **Blocked-ticket re-resolution across a workflow cutover is
  delivery's join, over engine's projection** (v5 §7.19; `core_dsl
  .md`'s §6 cutover). When a bundle flip retires the workflow
  sequence a blocked ticket's origin status belonged to, delivery
  re-resolves it: (a) the most recent status the ticket held that
  still exists in the new sequence, failing that (b) the status after
  the most recent *system status* it reached. (b) always terminates —
  system statuses are platform-fixed, the one part of a ticket's
  history no bundle change can delete. The join reads two logs and
  owns only one of them: the ticket's own status history is delivery's
  projection, and the active-bundle-version timeline is
  `systems/engine.md`'s ninth projection (current version + the
  sequence it became current, two rows per project) — delivery reads
  that rather than re-deriving its own copy, on the same boundary as
  everywhere else in this doc (engine is state of record, delivery is
  the protocol interpreting it). Target (Phase 7), alongside the rest
  of the workflow-bundle machinery this needs to have a subject at
  all — there is no declared workflow sequence to cut over from
  before then.
- **No boundary ticket, generalized: containers and the project alike
  carry their own progress — but the project is not a container**
  (ORC-105, design pass, superseding both ORC-103's own unmerged
  milestone-only version of this entry and this same ticket's own two
  earlier, since-reversed drafts — one that folded the project into
  the container shape, one that gave every queue entry a `flow:`/
  `opens:` pair; `docs/v5-design-decisions.md` §7.8; `docs/
  dsl-syntax.md` §15.6-§15.9). A container's or a project's status is
  which of its declared queues is current; a queue is a derived query,
  never a stored bucket, so there is no per-queue pending set for this
  system to own the way `ready_scopes` is engine's. Two relations this
  system dispatches against, both new: a queue's `flow:` target
  resolves against a work-item-type registry shared by container and
  plain-type declarations alike (`docs/dsl-syntax.md` §15.2, unified
  further at the fourth pass below) — no new
  dispatch mechanism whichever it resolves to, a `retro` or `setup`
  ticket opening a flow instance exactly like any other type, `setup`
  dispatching as its own anchor entry, first in the newly minted
  container's own sequence, never a value carried on the parent's
  dispatching entry, so the two never need to be the same declaration;
  a queue's `blocks:` relation to a sibling queue in the same
  declaration holds that sibling's entry open while the blocking queue
  carries unresolved work items — the general form of what used to be
  a single hard-coded boundary-blocking rule, now one relation the
  dispatcher reads wherever a workflow bundle declares it, milestone
  `main`→`retro` included. **The pause has no separate mechanism to
  build**: an `Urgent` ticket dispatches regardless of which queue a
  container or the project currently sits in (`docs/v5-design-
  decisions.md` §7.3, §7.10), which falls out of ordinary priority
  dispatch rather than needing a ticket-carried flag against its
  milestone the way ORC-103's draft required. Storage for "which queue
  a given container or the project is currently at," the
  `blocks:`-aware dispatcher, the declaration-graph acyclicity check
  that bounds nesting (`docs/dsl-syntax.md` §13), the
  `:live`-gates-`retro` interlock (§2.8), and the scan/setup/retro
  machinery itself are Target (Phase 7), filed as ORC-104 and blocked
  on this record; this entry is the shape it builds against.
- **Mint is not activation, and this system's dispatcher is the one
  that has to hold the two apart** (ORC-105's fourth pass, design
  pass; `docs/dsl-syntax.md` §15.8; `docs/v5-design-decisions.md`
  §7.8). A container instance can exist — created by business logic or
  a person, accepting groomed work into its own future queues — before
  its parent's own position ever reaches it; only reaching it makes it
  *active*, and only becoming active runs its `setup` entry's `flow:`.
  Two earlier framings of this same record had mint and activation as
  one event ("dispatch mints one instance and starts that instance at
  its own `setup` entry"; "minted one at a time as the prior one
  closes") and both are wrong for the case this system explicitly
  wants: grooming next milestone's `prep` during this milestone's own
  `main`. What this system owns, not yet built: the storage
  distinguishing "instances that exist" from "the instance that is
  current," and the two ways a container's position moves backward — a
  queue (a query over unresolved work items) un-resolving when its
  population refills, or a gate the container's own array cites
  throwing back to an earlier entry in that array. **The second way is
  a fifth-pass correction**, not a fourth-pass fact: the fourth pass's
  own "a container's anchor entries carry no gates, so they have no
  `throwback:` to borrow" stopped being true the moment gates and
  environments widened onto containers in the same pass that wrote it
  (`docs/dsl-syntax.md` §15.2, §15.4, §15.8) — a milestone sign-off
  gate between `main` and `retro` can throw back to `main` today, and
  this system's dispatcher has to honor that path alongside the
  un-resolve one, not only the one the earlier framing left standing.
  Filed against ORC-104 alongside the rest of this entry's Target list.
- **A fifth ORC-105 pass gave the dispatcher a cardinality bound to
  respect and closed a hole in the loader's own acyclicity check that
  this system's dispatcher would otherwise have inherited** (design
  pass; `docs/dsl-syntax.md` §15.6-§15.7; `docs/v5-design-decisions.md`
  §7.8). `milestone`'s `setup` and `retro` queues are declared
  `singleton: true` — bounded, this system's fifth-pass reading held,
  to 0 or 1 unresolved at a time — which is not something the loader
  can check (a queue's population is live ticket state) and is
  therefore this system's own dispatcher's job. **This reading was
  wrong, corrected at the sixth pass below** — see that bullet rather
  than treating "admitted and files `Blocked`" as this system's
  target behavior. Separately, the declaration-graph acyclicity check
  ORC-104 is filed to build (above) now has to treat a skeleton-less
  type — the project included — as a graph node, not only a
  `container`-skeleton type: the fourth pass's narrower node set
  excluded the exact edge a project/container cycle runs on
  (`milestone.main` → `flow: project`, `project.build-out` → `flow:
  milestone`), so a loader built against the fourth pass's own record
  would have let that cycle through. Nothing in this system's own
  dispatch logic changes shape from the acyclicity correction — it is
  about what the loader accepts before this system ever sees a bundle
  — but the Target build has to read the corrected record, not the
  superseded one.
- **A sixth ORC-105 pass corrected the fifth pass's own singleton
  reading and gave this system's dispatcher a fact to check that the
  loader cannot: which type a fresh project actually starts from**
  (design pass; `docs/dsl-syntax.md` §2, §13, §15.6-§15.7; `docs/
  v5-design-decisions.md` §7.8). `singleton:` bounds a queue to at
  most one work item **ever assigned**, not 0-or-1 unresolved at any
  moment — a queue whose sole work item has reached `terminal` is
  *closed*, not empty-with-room, so this system's dispatcher must
  reject a second assignment outright rather than admit it and file
  `Blocked`, once one work item has ever been assigned to a singleton
  queue. This is a real behavior change from the fifth pass's own
  record, not a rewording: "admit and file `Blocked`" and "reject
  outright" dispatch differently on the same input. Separately,
  `entry:` on a workflow bundle's own `bundle.yaml` names the type
  onboarding dispatches a fresh project from — this system reads it
  rather than inferring a starting point from which declaration looks
  project-shaped, the identical inference this record's own earlier
  passes leaned on informally without the loader ever having checked
  it. Neither correction changes this system's shape, only what its
  dispatcher and its onboarding path each read and enforce; both are
  ORC-104's to build, alongside the rest of this entry's Target list.
- **ORC-31 (design pass) extends the Host port's operation vocabulary
  for feature-lifecycle PR management and decline harvesting** —
  branch, PR-open, merge-forward, merge, review-comment read, marker-
  comment write, PR-label set, and check-status read, plus a diff
  read for reconciliation. Each is traced to the protocol clause it
  serves rather than to what GitHub happens to expose (v5 §7.17's
  first discipline): branch/PR-open/merge-forward/merge cover §7.5's
  topology (child PR → feature branch, feature PR → main; merge-
  forward absorbs drift continuously and surfaces a conflict as a
  real signal, never a silent resolution); PR-label set is how the
  plane marks `ci:docs`/`ci:code` for §7.7's job selection; check-
  status read answers back keyed to head SHA regardless of base
  branch, exactly as §7.7 requires; review-comment read and marker-
  comment write are §7.4's harvesting split, and they are two
  different GitHub comment kinds by design, not by convention —
  review-comment read pulls line-anchored review comments (the
  harvesting source), marker-comment write posts plane-authored,
  issue-level PR comments (bounces, findings). Keeping them on
  separate GitHub APIs is necessary but not, on its own, sufficient
  for telling human feedback from machine feedback — see the
  correction below. Diff read is this ticket's
  own restated invariant (conventions §11): the port moves refs and
  reads diffs, it never checks out. As with every earlier operation
  on this port, each lands in `HostPort.Actions` and `HostPort.Fake`
  in the same change — never one ahead of the other.
- **Author-review correction: harvesting classification filters by
  author identity, not by endpoint alone — a revision to §7.4's
  classification mechanism for the GitHub-PR surface, not an
  application of it** (ORC-31, design pass, second draft). The first
  draft treated "arrived via the review-comment endpoint" as
  sufficient to call a comment human, and presented that as §7.4
  holding unchanged. It doesn't hold as written: §7.4's rule covers
  *any* machine, because its premise is that machines mark, while
  endpoint-of-origin covers only *our* machine. Every third-party
  actor with review access — a GitHub App, a linter, a review bot,
  Claude Code's own inline review comments — posts through the
  identical review-comment endpoint a human uses; under
  endpoint-alone classification those harvest as human declines and
  thread into regeneration as author feedback, silently. **Revision:**
  review-comment read filters its results by author identity before
  anything is treated as harvestable — `performed_via_github_app` is
  reliable for GitHub-App-authored comments, `user.type == "Bot"` is
  reliable for bot accounts, and either excludes a comment from the
  human bucket. **Residual, named rather than hidden:** a bot
  authenticating with a human's personal access token is
  indistinguishable from that human at the API; nothing here closes
  that gap, and no fix is known. This is the strongest of the three
  mechanisms considered (markers, endpoint-alone, author-identity)
  because it needs no third party to cooperate with a convention it
  has never heard of — but it is a revision of §7.4's text ("anything
  unmarked... is human feedback") for the surface where we don't own
  the store, not a restatement of it. Markers are unchanged for *our*
  own machine (marker-comment write); author-identity filtering is
  what now stands in for "unmarked" on the review-comment side.
  **Placement correction (ORC-31, design pass, second author review):**
  the first draft of this correction recorded the revision here only,
  leaving `docs/v5-design-decisions.md` §7.4 still reading the
  superseded marker-only sentence — the source of truth disagreeing
  with the system doc about which rule is live. §7.4 now carries this
  mechanism, its reason and its residual directly; this bullet is the
  fuller argument the doc text points back to, not a second place the
  decision was made.
- **List-shaped read operations page to exhaustion; neither asserts a
  bound it hasn't measured** (ORC-31, design pass, author-review
  correction). `review-comment read` and `check-status read` are both
  list reads with no natural cap — a contested review on a real gate
  decline is not a handful of comments. This project has already
  shipped the single-page version of this defect once, in the sibling
  adapter: ORC-101 (Triage) found the Go pipeline's
  `internal/host/github/github.go` `ListAgentRuns` reading exactly one
  `per_page=100` page with no filter, on the reasoning "anything past
  100 runs ago is not it" — reasoning that turned out wrong under
  sweep noise. `HostPort.Actions` follows GitHub's pagination (the
  `Link` header / cursor) to exhaustion for both operations rather
  than reading one page and assuming the rest doesn't matter;
  `HostPort.Fake` mirrors the same contract — its fixtures include a
  multi-page case for each, not only a single-page one — so the
  offline sim ring can catch a caller that assumes one page is
  everything. No cap is imposed at this layer; a rate/cost bound, if
  one turns out to be needed, is a dispatch-budget decision (v5
  §7.12.1), not a silent truncation here.
- **The marker vocabulary is a typed module, scoped to GitHub PR
  comments only** (ORC-31, design pass; extends the marker-retirement
  bullet above rather than reopening it). `HostPort.Marker` (naming
  follows `HostPort.Actions`/`HostPort.Fake`'s own pattern) holds a
  closed enum of kinds, each with a render function producing the
  exact comment body and a parse function reading one back —
  `{:ok, {kind, payload}} | :not_a_marker` — so no call site builds a
  marker string by interpolation and no call site greps a comment
  body for a substring. **`parse/1`'s named caller (ORC-31, design
  pass, author-review addition): marker-comment write's own
  idempotency check.** Before posting a new bounce, the plane lists
  the PR's existing issue-level comments and parses each with this
  function to check whether the scope-violation marker for this gate
  decline is already there, so a re-triggered decline path (a retry,
  a resumed pass) doesn't post a second `Ready for rework` comment.
  This is a read of the plane's own issue-level comments and is not
  the harvesting read — `parse/1` never sees a line-anchored review
  comment, and harvesting's classification (the correction above)
  never calls it. Phase 4 needs exactly one kind to start: the
  scope-violation bounce already named in §7.5 ("a plane-authored
  marker comment naming the paths, `Ready for rework`"). Later kinds
  — §7.11's findings marker, §7.14's bug-intake sequence stamp — join
  the same closed enum when their phase needs them; they are not
  invented ad hoc at whichever call site first wants one. This module
  governs the write side only. **The read side needs no parser of its
  own only because the plane never authors a line-anchored review
  comment — an invariant to keep, not a free property, and it is
  recorded here so the next pass sees it before it breaks it** (ORC-31,
  design pass, author-review addition). Today that premise holds
  because no plane operation posts a line-anchored comment at all,
  which is what makes the property cost nothing rather than something
  enforced. If a later ticket adds one — a review-thread reply is an
  obvious want when declining a decline — that comment would arrive
  through the same review-comment endpoint the harvesting read
  otherwise treats as candidate human feedback, and it would harvest
  as feedback on its own author's comment with nothing here to catch
  it. Should that operation ever land, harvesting's read side needs
  the same author-identity filter the correction above puts on
  review-comment read generally — excluding the plane's own GitHub
  identity alongside third-party bots and Apps — not a return to
  string-parsing. Until then, "unmarked" means: arrived as a review
  comment, and not filtered out by the author-identity check above —
  not, as the first draft had it, simply "arrived as a review
  comment."
- ~~**The Fake's forge state lives in `Catapult.Delivery.Store`, not a
  second process.** Branches, open PRs, posted comments and check runs
  are exactly the same shape of problem `dispatch_run` already solved:
  state one test writes and the same test reads back, sandboxed
  per-test under `mix test`'s async runs. `HostPort.Fake` gains no
  GenServer identity and no in-memory map for this — new Store-owned
  Ecto tables carry it, the same persistence substrate every other
  delivery record already uses, so the fake stays sandbox-safe without
  inventing a second state mechanism this system would then have to
  keep consistent with the first.~~ **Corrected (ORC-31, design pass,
  author review): a per-test supervised process, not a Store table.**
  The struck claim's precedent doesn't transfer: `delivery_dispatch_runs`
  is written by the *real* adapter as well as the fake —
  `HostPort.Actions` opens that record on every live dispatch, because
  it is production state the plane genuinely keeps — while branches,
  PRs, comments and check runs have no production writer at all; GitHub
  holds them, and the real adapter only ever reads them back. New Store
  tables for those would exist solely for the fake, inside the plane's
  production schema, with nothing in production ever writing a row. The
  reason given for refusing an in-memory fake — sandbox safety under
  `mix test`'s async runs — has an answer that needs no schema: a
  per-test supervised process, isolated by construction, since no
  database is involved there is no sandbox to need. `HostPort.Fake`
  gains a GenServer per test (started and stopped with the test, like
  any other test-owned process in this codebase) holding branches,
  PRs, comments and check runs in memory, keyed to that process — not
  a Store table. Store-backing forge state may still turn out to be
  the right call — the fake surviving a `Repo` restart, or the sim ring
  wanting to query forge state through the same surface as everything
  else, are real arguments for it — but that argument wasn't made here,
  so this entry doesn't make the decision on its behalf.
- **No HTTP-mock-server-based fake** (ORC-31, design pass; refusal,
  scope: system:delivery). The Actions adapter's own code path could
  run unmodified against a stub GitHub server (Bypass, a cassette
  replay of the REST API), and that will look like the easier fake to
  write. Refused: it fakes the vendor's transport, not the protocol —
  the exact property v5 §7.17's second discipline names ("the fake is
  written against the protocol rather than mirroring the adapter"),
  and an HTTP-level stub would quietly start requiring GitHub's own
  URL shape, pagination and rate-limit behavior to keep the fake
  alive, which is the coupling the fake exists to avoid. `HostPort
  .Fake` stays a plain Elixir implementation of the behaviour with no
  HTTP dependency at all.
- **The sim-style test ring drives a full branch → PR → comment →
  harvest → merge-forward → merge scenario through `HostPort.Fake`
  alone, with no network** (ORC-31, design pass). It lives beside the
  rest of this system's suite, under this doc's own file map
  (`test/catapult/delivery/`) — no separate ring or `live` directory,
  the same reasoning `docs/non-goals.md`'s no-`test/live/`-directory
  entry already gives for a different tag. It carries no `:live` tag
  itself: nothing in it crosses a real network boundary, so the ring
  is an ordinary async suite member, not a live one. Populating this
  ring is scope, not scaffolding — the same standing principle
  `systems/generation.md` states for the dispatch fake — because it
  is what lets protocol work on branches, PRs and harvesting continue
  to be exercised, and continue to be provably correct, on a day
  GitHub itself is down.

## Initial vs target

Initial (Phase 4): the host port + fakes; feature lifecycle through
the two gates; PR + harvesting; lifecycle projected into the plane's
own read models, which the work surface renders — there is no third
party in this path. **Narrowed at ORC-9**: the host port's
dispatch-facing slice — context-fetch, result-report, OIDC
validation, run correlation, and its in-memory fake — lands in Phase
3 with the generation executor (`systems/generation.md`), ahead of
the rest of this system. It is one seam with two consumers arriving
at different times, not two ports: the slice generation needs now is
a subset of the same host port this doc already claims, not a
parallel one this ticket invents. The handler logic for that slice —
OIDC validation, run correlation, context/result payloads — lives
under this doc's own file map; **what serves it does not**
(`systems/foundation.md`'s design review finding): the endpoint rides
a second path on foundation's existing health listener, reached
through an `api_surface/0` declaration rather than a router of this
system's own, because the general composed router waits for
dashboard's Phase 4/7 web layer. **Narrowed again at ORC-10**: the
repo-reset operation above, and the `Contents: read and write` grant
it draws on, land with it — a second sliver of Phase 4's host port
pulled into Phase 3 for the same reason the first one was, because the
milestone boundary test needs it now. **ORC-31 (design pass) records
the shape of the rest of Phase 4's host port** — the operation
vocabulary, the marker-vocabulary module and the sim-style test ring,
above — ahead of the dev pass that builds it. **ORC-31's dev pass
lands that shape**: the operation vocabulary in both `HostPort
.Actions` and `HostPort.Fake`, `HostPort.Marker`, and the offline sim
ring. What stays open at Phase 4 is lifecycle projection proper —
wiring these operations into ticket-state projection and the gate
machinery that decides when a bounce, a merge-forward or a merge
actually fires — which this ticket's own scope excludes and no ticket
has yet built. Target
(Phase 7): the whole of v5 §7,
including the delivery-DSL extension registered with core_dsl, the
declared review sequences and environments of §7.19, and the outbound
mirror in place of the Linear adapter.

## Depends on

substrate, engine (state of record), foundation (serves the
dispatch-facing host port endpoint on its listener), generation (the
chain whose progress it projects), core_dsl (the workflow bundle's
declared statuses and environments, v5 §7.18-§7.19), dashboard (the
work surface — a hard dependency, since nothing else renders the
loop). Req for the GitHub client.
