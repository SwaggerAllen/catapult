# generation — reasons

The reason behind each rule in `systems/generation.md`, keyed by the rule's id (orchestration's DESIGN §4). Read one with `pipeline reasons generation#n` before changing the rule it belongs to.

## #8

That class is easy to miss because the two conditions coincide in `bundles/default`
for every `<arch> → ref` citation — a tier names itself as both the edge's `source`
and `declared_in`'s leading segment — and `Extraction`'s own moduledoc names only
the second condition ("a `declared_in` path whose leading tier differs from the
tier being committed"). Sixteen `reference`/`fulfills` instances exist in
`bundles/default`, and seven fall into the join-target-`source` class, each because
its `source` names a join-target node type: `fulfills comp → resp` (`source: comp`,
declared in `sysarch`), `fulfills screen_coll → screen` (`source: screen_coll`,
declared in `frontend_sysarch`), `reference journey → screen` (`source: journey`,
declared in `screens`), `reference resp → journey` and `reference resp → screen`
(`source: resp`, both declared in `requirements`), `reference screen_coll →
journey` (`source: screen_coll`, declared in `screen_collarch`), and `navigation`'s
own `screen → screen` (`source: screen`, declared in `screens` — `screens` never
commits under the name `screen`, the identical shape the other six have). Only the
nine `<arch> → ref` instances (`comparch`, `subcomparch`, `impl_backend`,
`ui_collarch`, `ui_subcomparch`, `impl_ui`, `screen_collarch`,
`screen_subcomparch`, `impl_screen`) satisfy both conditions and are extracted.

Every `type: dependency` instance `bundles/default` declares — ten in total:
`comp↔comp`, `subcomp↔subcomp`, `ui_coll↔ui_coll`, `ui_subcomp↔ui_subcomp`,
`screen_coll↔screen_coll`, `screen_subcomp↔screen_subcomp`, `ui_coll →
design_system`, and `calls`/`renders`/`uses_shapes` (three more, declared in
`frontend_sysarch`'s own draft rather than `screen_coll`'s or `ui_coll`'s) — fails
the identical `source`-identity gate, for the identical reason: none of `comp`,
`subcomp`, `ui_coll`, `ui_subcomp`, `screen_coll` or `screen_subcomp` ever commits
a `DraftCommitted` of its own. So every context walk reading one of these
(`comparch`'s, `subcomparch`'s, `ui_collarch`'s, `ui_subcomparch`'s,
`screen_collarch`'s and `screen_subcomparch`'s own `dependency` entries —
`impl_backend`, `impl_ui` and `impl_screen` walk the identical sibling-dependency
entry their own `*subcomparch`/`*collarch` counterpart declares
(`self.parent.dependency -> subcomp.handle.fragments[pubapi]` and the
`ui_subcomp`/`screen_subcomp` equivalents), not a different one, so the same
emptiness reaches them too — and `comparch`'s and `screen_collarch`'s own
`fulfills` walks, and `frontend_sysarch`'s own `calls`/`renders`/`uses_shapes`
walks, too) resolves to `[]` and stays vacuously satisfied regardless of tier
ordering. `systems/platform_content.md`'s ORC-232 entry records the
`subcomp↔subcomp` instance of this as live and broken; the same `source`-identity
gate excludes every instance above, not only the ones typed `dependency`.

The two `type: policy_application` instances
(`bundles/default/edges/policy_application.yaml:24,35`) are a third shape, not a
second instance of the class above. Their `declared_in` values are
`policy.structural` and `policy.required` — not a `<tier>.draft....` path at all,
so `self_sourced_path/2` has nothing to navigate: it returns `:skip` on the shape
mismatch before `instance.source == tier_name` is even asked. Both are set at mint
time off a marker the minting draft itself carries (a `<policy>` element's
`<structural/>` vs. `<required>` child — that edge file's own comments), never
extracted from any committing tier's draft body at all.

## #17

The deciding reason is the retry promise below: a grammar-invalid commit returns a
typed error the agent retries with, *bounded within the same run* — and only a
synchronous request/response can hand that back to a process still executing. A
marker comment can announce a result to a human later; it cannot hand a typed
validation error to the agent that is still running. Marker comments stay the right
shape exactly where `systems/delivery.md` keeps them — GitHub PR comments, a
surface whose cadence the plane doesn't own — but a result report is plane-to-plane
over a channel the plane owns both ends of, so the marker's reason for existing
doesn't transfer here.

## #18

`oauth_org_not_allowed` is credential-shaped but not usage-shaped — the org has
disallowed the OAuth credential outright, which is the same kind of problem
`authentication_failed` already reports as `other_failure` rather than limit-class
— so it joins that bucket rather than triggering a failover that would mask a
configuration problem needing a fix, not a workaround. `model_not_found` and
`invalid_request` are request-shaped, not usage-shaped, and join `other_failure`
for that reason.

`other_failure` stays undifferentiated by design, not by gap: the terminal `result`
object also carries `stop_reason`, and `stop_reason == "refusal"` is a real,
documented signal for detecting a declined request — the harness chooses not to
consume it because nothing downstream of the `other_failure` bucket reads a finer
split today, not because the CLI fails to expose one. The undifferentiated bucket
is a recorded choice, not an absence of signal.

## #19

A composite action under this repo's own `.github/actions/**`, referenced
cross-repo from every bound project's workflow (`uses: <this repo>/…@ref`), would
tie every dispatched run forever to this repo's own git history instead of to the
reviewed commit its own bound-repo workflow file already pins — the mirror image of
the coupling §1.2's reason closes off, one hop later — and `.github/actions/**` has
no owner in this repo (`systems/README.md`'s unowned-paths list doesn't carry it),
so creating one is the author's call, not a ticket's. A script fetched from the
plane at run time would give the plane a live code-serving role beyond its two
settled dispatch endpoints (context-fetch, result-report), a new authenticated
surface bought for no protocol gain, and it ties an in-flight run's behavior to
whatever the plane's *current* deploy happens to serve rather than to the commit
its own workflow file pinned when the run started.

## #21

Claude Code documents `api_retry`'s `error` categories for retryable API errors
and, separately, a claude.ai usage limit as something that stops a run mid-task — a
`-p` run does not wait for the reset — without saying which event a headless run
emits when it does. Two shapes are possible, and the rule is right on one and blind
on the other: a `429` arriving as `api_retry` with `rate_limit` fails over to the
API key as intended; a terminal `result` of `error_during_execution` with no retry
event reports `other_failure` and never fails over, which loses exactly the case
the pair exists for. The first run that hits the ceiling settles which is real —
its `stream-json` output is in the bound repo's Actions log for that run — and
until then an `other_failure` on the subscription credential whose `result` names a
usage limit is this rule's failure mode, and reads as one.

## #25

This satisfies the invariant rather than contradicting it: "no memory across
dispatches" is a claim about the *dispatched run*, which still re-renders its
context walk and starts clean every time — the count lives once, in the plane's
log, the same place every other derived answer in this system already lives
(`systems/engine.md`'s "no in-memory pending-set" doctrine, one layer down), not in
a table row or an Oban attempt counter. An Oban attempt counter is the wrong home
for a concrete reason: an Oban attempt count is scoped to one job, and the
uniqueness key that turns a re-announced ready scope into one dispatch (above) is
held only for the scope's in-flight window — once that window closes, a redispatch
is a *new* job starting its attempt count at zero, so the very mechanism that
dedups dispatch would silently reset the failure count it would have to hold. The
log has no such window.

## #27

Two decisions are recorded where they would be edited rather than here:
`since_sequence` is caller-supplied rather than computed inside `execute/2`
(`Catapult.Engine.Commands.DeclineGate`, on this system's purity floor), and the
reset boundary is neither `DraftCommitted` nor a position in the resolution
sequence — `CommentFeedback`'s own moduledoc names both alternatives, their failure
modes, and the shipped bundle that breaks the second.

## #30

`CommentFeedback.since_last_resolution/2` is a per-`node_id` fold
(`systems/engine.md`); a test asserting only "regeneration happened" cannot tell
that fold apart from one bucketed by project or by gate — which is exactly the
class of bug this same fold's history already produced once (the position-based
`since_sequence` inference broke the moment a workflow declared more than one
gate). Two nodes, one declined, is the cheapest fixture that makes the two
hypotheses disagree, and the reasoning is orchestration's own: assert the thing
that would go wrong, not a side effect every wrong implementation produces too.

## #31

What the toy seed already proves — the graph-native chain,
`self`/`self.parent`/`all.*` walks, every tier reachable from `comparch` down
through `impl`, at least one instance of every edge type, which is the whole of
what `ContextResolver` resolves — needs no input-role content; the input-role
assertion above is additive coverage for the direct-read path, not a replacement
for it.

## #34

**The cutoff, argued rather than picked.** The harness's own worst-case wall clock
for a *legitimate* run is bounded, not open-ended. The run-agent step tries up to
two credentials, each bounded at the 1800s subprocess timeout
(`catapult-dispatch.yml`); a credential that itself hits that timeout reports
`other_failure` and does not fail over (the harness's own exception handler
`break`s rather than `continue`s), so the only path that reaches a `:success`
outcome costs at most two such windows — 3600s. A `:success` outcome that then
fails grammar validation retries in the report step, bounded at two further
attempts (the entry below), each against that same 1800s timeout — up to another
3600s. 7200s (two hours) is the harness's own ceiling for a run that ends in
`:success`; three hours is that ceiling with room for GitHub's own queue/startup
delay before the job even begins running, not a second independent guess.

## #37

A `vars.STUB_MODE` set once on `SwaggerAllen/catapult-test` is out-of-band state
the plane doesn't control per dispatch: it would apply to every future dispatch to
that repo regardless of which run needs it, and reading it back to know whether a
given run *was* stubbed would mean a second source of truth beside
`delivery_dispatch_runs`. A `workflow_dispatch` input costs nothing new: `run_key`
and `credential_order` already ride this channel, and stub mode is exactly the same
shape — plane-decided, per-dispatch, visible in the run's own log.

This checkout is what the poll-deadline entry below means by "a checkout plus a
report call".

## #38

That is the deliberate mirror of `sweepable_project?/1`'s own no-row answer
(`true`, above): no row is the ordinary-project case for both predicates, but the
two questions they answer point opposite ways on it — an unbound project is
trivially sweepable (nothing exempts it) and must never dispatch stubbed (nothing
opts it in), so the same absence reads as `true` on one and `false` on the other.

## #40

Returning it would remove the fixture push, this checkout step and the
`.catapult-stub/` namespace together, but the checkout is not a cost stub mode
introduces — a real run needs one regardless — so a checkout-free retrieval path
built for stub mode alone would leave two mechanisms doing the one thing the
harness needs on every dispatch, stubbed or not.

## #42

This is deliberate, not a missed opportunity to cap it: the boundary pass exists to
be as close to production as the toy chain gets without a model in the loop, so it
runs the whole chain agentless, and a real-model run confirms the production case
separately and strictly afterward — sequencing the two within one boundary run is
its own design (`systems/delivery.md`'s ORC-216 entry is why they cannot run
concurrently regardless: at most one `:active` test project). A round cap, or a
second, shallower test beside a full-walk one, would be sizing the every-milestone
suite to a depth nobody has measured.

## #43

`Provisioning` exposes no node-status read, so a new run is the fact the suite can
actually observe; asserting on it rather than on the approval count is what makes
the assertion prove the mechanism advanced the walk rather than merely that a
compare- and-swap succeeded.

## #44

`bundles/default/tiers/*.yaml`'s downward-cascade graph fixes the walk's *approval
depth* — how many sequential approve-then-dispatch rounds a complete walk takes —
because every join-target tier (`comp`, `subcomp`, `screen_coll`, `ui_coll`,
`ui_subcomp`, `screen_subcomp` and the rest) has no `draft:` block at all, so
`Extraction.mint_status/2` returns `:approved` for it at mint time rather than
`:absent`, and it never dispatches or needs a human (or `approve_drafts/2`) to move
it. Every context walk this bundle writes — `self.parent`, `self.reference`,
`all.<tier>` alike — folds the identical `status == :approved` requirement over
whatever it resolves to (`walk_ready?/2`); the two kinds of tier differ only in
*how* a target reaches `:approved` — instantly at mint for a join target, or
through its own generate-then-review-then-approve cycle for one that carries a
`draft:` block — not in whether the requirement applies. So a tier costs an
**approval round** only when it carries a `draft:` block *and* something has to
wait on that approval to become ready; it still costs **dispatch waves** — a draft
and a review, each a real run the sweeper has to find and the suite has to poll for
— whenever it carries a `draft:` block at all, approval-gated or not. Tracing the
toy raft's longest approval-gated chain from `feature_expansion` gives exactly
**three** gate-bearing tiers: `feature_expansion` → `requirements` → `sysarch` —
every tier past `sysarch` reads either a join-target's mint-time `:approved` or
`sysarch`'s own approval, never a fourth tier's *approval*. But most of those tiers
still carry their own `draft:` block, and the suite's loop does not stop at the
last approval: it stops at `remaining == 0` with nothing left `:drafted`, which
means every one of those tiers' drafts and reviews still has to dispatch and
settle. This is depth, not breadth: `per(comp)`/`child_of` fan-out still depends on
what a draft itself mints, which the tier bundle alone cannot predict, so the
number of *nodes* dispatched within a wave stays unmeasured and the deadline still
needs headroom for it — depth fixes how many waves the suite must wait through, not
how much work each wait costs.

**Under `settled?`/`drained?` (ORC-235), no walk in the raft costs more than this
floor prices.** `comp` mints at `sysarch`'s `DraftCommitted` (`CommitPath`'s own
private `commit_draft/3` calls `Extraction.mints/4` at commit time, before
`sysarch`'s own review or approval), but `comparch`'s `self.parent.handle` walk
onto it does not read that mint-time `:approved` bare: `settled?/2`
(`systems/engine.md`'s ORC-235 entry) resolves a join target by deferring to its
minting parent, so `comp` is `settled?` only once `sysarch` itself is approved —
exactly the wait this entry costs for a tier reached through a `draft:`-carrying
ancestor: that ancestor's own approval, not merely its draft. Tracing every walk in
the raft against `settled?`/`drained?` finds no site where the derived graph waits
on more than that: `frontend_sysarch`'s `all.comp.handle`
(`systems/platform_content.md`'s ORC-235 entry) reduces, via `drained?(comp)`'s own
recursion through `sysarch`, to the identical `sysarch`-approved condition
`all.sysarch.handle` already required, so the front-end and back-end branches land
on the same wave rather than one gating the other — the "run alongside each other"
claim below holds. Nor is there a second, stronger mechanism to price separately:
`systems/engine.md`'s own ORC-235 entry rejects a declared tier sequence and
derives order purely from `context:` walks, so "no parallelism between tiers" is
exactly the per-tier, per-walk waiting `settled?`/`drained?` produce — never a
blanket ordering over tiers with no read relationship between them, which is what
would be needed to exceed this floor. The same reasoning is why `non_goals`, `ref`
and `vocab` cost nothing added here: `drained?(vocab)` requires every existing
vocab entry `settled?` rather than reading an empty list as vacuously satisfied,
but vocab's own draft-and-review (2 waves) lands well before `comparch`'s walk onto
`all.vocab.handle` is first checked (15-plus minutes in), so that wait is already
spent by the time anything asks for it.

The two branches run alongside each other, not in sequence, so they do not add on
top of each other — but fragment-authorship, a third relationship distinct from
mint-ancestry and approval-ancestry, does not move the count everywhere it applies
the same way, and it applies in three places above, not one.

At the `ui_collarch`/`screen_collarch` step, it happens not to move the count.
`ui_collarch` walks `self.parent.uses_shapes -> comp .handle.fragments[pubapi]` and
`screen_collarch` walks `self.parent.calls -> comp.handle.fragments[pubapi]`
(`bundles/default/tiers/ui_collarch.yaml:38`, `screen_collarch.yaml:45`), and
`comp`'s `pubapi` fragment is authored by `comparch`'s own `produces:`
(`comparch.yaml:58`), not by `sysarch` — so `comp` reaches `:approved` at
`sysarch`'s mint (mint-ancestry) and needs no wait on `comparch`'s own approval
(approval-ancestry), but the *content* the front end actually reads is written by
`comparch`'s draft (fragment-authorship). It does not move the count *at this one
step* because both branches finish their first tier two waves after `sysarch`'s
approval regardless of which relationship governs `ui_collarch`'s wait — they land
in the same wave either way. It is exactly the gap ORC-235's own second defect is
about — a context walk's readiness check passes at `comp`'s mint-time `:approved`
while the fragment content it reads is still being written by `comparch` — and this
entry does not depend on that gap being closed.

It does move the count at the `impl_*` step, in both branches, which is why the
waves above cost `impl_backend` after `subcomparch` and `impl_ui`/`impl_screen`
after `ui_subcomparch`/`screen_subcomparch` rather than alongside them.
`subcomp`/`ui_subcomp`/`screen_subcomp` are join targets with no fragment content
of their own — every field they carry is a mint-time copy — so unlike the
`comp`/`comparch` step above, there is no mint-ancestry route into an `impl_*` tier
that bypasses the tier that writes the content it reads: fragment- authorship is
the *only* relationship in play, not one of two that happen to agree. Costing
`impl_backend`/`impl_ui`/`impl_screen` as concurrent with their `*subcomparch`
sibling would let the suite call the walk complete while an `impl_*` draft was
rendered against an empty `pubapi` fragment — precisely the class of failure a full
walk exists to surface, so the wave count above prices it as sequential.

**That wait is priced, not enforced.** `impl_backend`'s `self.parent.dependency ->
subcomp.handle.fragments[pubapi]` (`impl_ui`'s and `impl_screen`'s own reads are
the identical shape one tier over) is the same `subcomp↔subcomp` `dependency` walk
`subcomparch`'s own context entry already is, and the extraction-gate entry above
covers it: no `dependency` instance is extracted regardless of which tier's context
declares the walk, so it resolves to `[]` and is vacuously satisfied whether or not
`subcomparch` has run. `impl_backend`/`impl_ui`/`impl_screen` are therefore ready
the same wave as their `*subcomparch`/`*collarch` sibling — once
`subcomp`/`ui_subcomp`/`screen_subcomp` is `settled?`, i.e. once
`comparch`/`ui_collarch`/`screen_collarch` is approved — not one wave after it.
Pricing them as sequential anyway does not undercount: it charges a wait the graph
does not enforce, which only widens this floor's own margin, and it stays priced
this way on purpose, since closing the extraction gap would reintroduce the wait
for real and a floor that assumed otherwise would need re-deriving the moment it
does.

The front end's 8 waves is the longer of the two branches and is what the walk
actually waits on after `sysarch`'s approval. The floor to `remaining == 0` is 15
(the three approval-gated rounds) plus 12 (the front-end branch) — 27 minutes —
before the breadth headroom below is added on top.

## #47

ORC-216's own lifecycle guard closed the window after a test project stops being
current; live-suite run 25 found the window *before* it starts current: the
sweeper's tick interval runs independently of `Provisioning.reset_and_intake/2`'s
own write — one Contents-API `PUT` per entry in the caller's `files` map
(`HostPort.Actions.put_all_files/2`; seventeen of them for
`ToySeed.reset_files/0`'s own map, the live suite's own seed) — so a tick landing
inside it dispatches against a repo missing whichever piece hasn't landed yet: the
workflow file, a stub, or the raft. Runs 866–869 dispatched at heads `d2e0f8cc` and
`37733f90`, by which point eight or nine of the nine stub fixtures had already
pushed — what was still missing was the workflow file and the seven raft docs. The
missing workflow file is what the dispatched runs actually hit: they executed the
pre-#144 harness and died at the report step with `FileNotFoundError:
context.json`, one to two seconds before the fix reached the repo.
`sweepable_project?/1`'s own body (`Catapult.Delivery.Store.sweepable_project?/1`)
is a catch-all — `%Project{test_project_state: :active} -> true`, `%Project{} ->
false` — so a `:provisioning` row falls to the `false` clause; the only code the
guard needs is `:provisioning` in the schema's own `Ecto.Enum, values:` list
(`systems/delivery.md`'s entry above covers this, and without it the row fails to
load regardless). Neither sweep site needs a check of its own: both
`Sweeper.sweep_project/2` and `DispatchWorker`'s own `still_sweepable/1`
re-validation read `sweepable_project?/1` rather than holding a cached readiness
bit, so the schema's value list is the whole of it.

## #48

A missing key is not a gap the live suite tolerates by exercising a narrower chain
— the entry above keys the lookup by `root_tag` rather than by tier precisely so
one fixture serves every tier sharing a root_tag, and that same collapse means a
single missing key fails every tier that shares it, not just one.

## #49

"Report the result"'s own fallback keeps one meaning rather than gaining a second:
since the read step cannot fail past this point without writing something, "no
outcome.json" means what it claims to — the body-producing step (real or stubbed)
crashed somewhere the harness gave it no chance to report.

## #52

ORC-225 (#48) checked that every root_tag has a fixture; it never checked that the
fixture the plane would actually commit still satisfies its tier's own grammar, and
`ToySeedChainTest`'s own name — "the toy seed generates and validates through every
tier, offline against the fake" — was true only of the fixtures it read. A tier
whose fixture and grammar diverge is otherwise invisible until a live run reaches
it: `CommitPath.commit_draft/3` rejects the body before anything commits, so no
`DraftCommitted` event fires, nothing downstream dispatches, and the run's only
signal is silence until its deadline expires — 33 minutes to learn what an XSD
validator answers in under a second offline.

The frontend five are ORC-225's own fixtures (`713204a`); ORC-232 was the last
pass to modify them, one PR before ORC-235 edited the grammars two of them
validate against and left them behind. Between ORC-225 writing them and ORC-235
breaking them, `ui_collarch` and `screen_collarch` had no execution history of any
kind, offline or live: neither tier could dispatch before ORC-232 made
`ui_coll`/`screen_coll` mintable at all, and the live suite's last green run
before the incident, run 28 (`fee6210c`, ORC-228), predates that change. Run 29
was the first live run that could ever reach either tier, and it reached them
already broken — nobody had reason to suspect the fixtures, because nothing had
ever run them.

## #53

Grammar conformance (#52) is necessary and not sufficient: `minOccurs="0"` lets a
fixture validate while omitting content a downstream tier depends on to mint
anything at all. `feature_expansion.xml` has carried no `<vocabulary>` block
since ORC-225 wrote it, so `vocab`/`vocab_review` have never had a path to
dispatch from this raft — a gap #48's existence check and #52's conformance check
both pass cleanly, because an absent-but-optional element fails neither.
`frontend_sysarch.xml`'s relocated loci (ORC-235) are the same shape one ticket
later: the elements exist in the schema, `minOccurs="0"` again lets the fixture
validate without them, and ORC-236's extraction for `renders`/`calls`/
`uses_shapes` and the two same-tier `dependency` instances has run against a
fixture that supplies none of it. Neither gap is a schema violation, so neither
would have surfaced from #52's direct validation — only a full offline walk
through `Extraction`/`Store` mints far enough to notice nothing came out the
other end, which is why the two checks are separate mechanisms rather than one
assertion doing both jobs.
