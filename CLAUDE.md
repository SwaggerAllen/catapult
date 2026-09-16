# Catapult — repo specifics

What only this repo can say. The pipeline protocol (roles, states,
markers, mutex, file maps) is injected into every agent run from the
pipeline checkout (`.pipeline/prompts/repo-context.md`) — none of it
is restated here, and where that file and this one disagree about
protocol, that file wins.

## What this is

The Catapult platform: an Elixir control plane (Commanded + Oban)
that runs a documentation-generation chain and a ticket-delivery
pipeline for the projects it builds. Design source of truth:
`docs/v5-design-decisions.md`. Build sequencing:
`docs/build-plan.md`. Coding rules with rationale:
`docs/conventions.md` — read it before writing code; every rule
carries its reason. Negative space: `docs/non-goals.md` — proposing
against it means arguing with a recorded decision, and saying so.
Architecture: `systems/*.md`, one doc per system with a file map.
DSL grammar: `docs/dsl/bundle.md`, `chain.md` and `workflow.md`
(normative; each rule carries an id and a reason in its
`.reasons.md` sibling, and wins over the v4 spec).
`docs/dsl/example/` is the default pair written in that grammar, with
a checker that derives what the rules say is derived;
`docs/dsl/retired-spec-index.md` maps the sections of the retired
`docs/dsl-syntax.md` onto the rules that replaced them.

## Toolchain

Pinned in `.tool-versions` (Elixir 1.17.3-otp-27 / OTP 27.3.4 —
27.2 and earlier reject builds.hex.pm's TLS cert with
`key_usage_mismatch`); CI enforces it, and `mix.exs` floors match
(`~> 1.17`). Dep series ride current stable — the `deps.audit` gate
forced the bump the day it armed (the old interim pins are retired;
ORC-3's coherence pass, done ahead of the pipeline). An out-of-band
toolchain older than the pin cannot compile the deps; the pinned
toolchain is the only supported one.

## Layout

- `lib/catapult/` — plane systems (see `systems/*.md` for the map).
- `components/substrate/` — the shipped platform substrate: a
  separate mix project, path-dep'd, **with its own test/format/credo
  suite that CI runs separately** — run both.
- `bundles/` — DSL bundle content, both axes (v5 §7.18), each a
  single forked-and-tailored directory rather than a loader-composed
  layer (`bundle.md` #7): the chain bundle (`default`) and the
  platform workflow bundle (`default-flow`: default review sequence,
  `dev`/`staging`).
- `screens/` and `storybook/` — **design-owned** (`pipeline
  .config.json`'s `designOwnedPaths`), and `storybook/**` is the one
  tree where authored **Elixir** arrives without a dev pass behind
  it: `storybook/screens/<name>/component.ex` plus its
  `.story.exs`. It is on `elixirc_paths` in every environment
  deliberately — off it, the whole gate set is blind to exactly the
  code nobody reviewed as code.
- `bin/preview-build.sh` — the branch preview
  (`pipeline.config.json`'s `preview.buildCommand`). It installs its
  own OTP/Elixir because the agent runners have none (below), and it
  **never exits non-zero**: the calling step is `set -euo pipefail`,
  so a failing preview would fail the agent job and stop tickets
  dispatching. Every failure publishes `preview/index.html` instead
  and says why on stdout.
- `priv/repo/migrations_infra/` — infrastructure migrations
  (Oban, EventStore); per-store migrations compose in as stores land.
- `seed-docs/` — **vendored SiegeEngine reference, frozen**: the v4
  spec (its **Appendix B** is what this repo's docs cite as "§B.2" —
  it was never in `v5-design-decisions.md`), the v4 default-bundle
  reference, and siege's own prompt chain. Read it when working on
  bundle content; `docs/v5-design-decisions.md` wins wherever they
  disagree, and `seed-docs/README.md` lists the three places they
  knowingly do. Siege is AGPL and `bundles/**` is Apache-2.0, but
  carrying text across is **authorized** (sole copyright holder, no
  third-party contributors, no users) — see its README; ORC-7 still
  writes fresh, for structural reasons rather than licensing ones.

## Verification (run all before claiming done)

```
mix deps.get --check-locked
mix deps.audit                       # hex.audit runs first, inside the alias
mix format --check-formatted
mix credo --strict
mix sobelow --exit --skip --ignore Config.HTTPS
mix compile --warnings-as-errors     # boundary compiler is in the set
mix xref graph --format cycles --fail-above 0
mix xref graph --label compile-connected --fail-above 0   # the ratchet
mix catapult.audit                   # root project ONLY — see below
mix test                             # needs Postgres; sandbox, async
cd components/substrate && mix deps.get --check-locked && \
  mix hex.audit && mix format --check-formatted && \
  mix credo --strict && mix compile --warnings-as-errors && \
  mix xref graph --format cycles --fail-above 0 && \
  mix xref graph --label compile-connected --fail-above 0 && \
  mix catapult.audit && mix test
```

Both blocks are the whole of conventions §2, per project — not a
subset. The gate set is a property of a mix project, not of the repo
(`systems/substrate.md`): the audit's globs are rooted at the working
directory — deliberately, since the task ships into every generated
project — so `mix catapult.audit` at the root never sees
`components/substrate/lib/**`. Run it in both, or run
`mix catapult.audit.all` from the root, which is the alias that does
exactly that (and needs `components/substrate/deps` resolved; it exits
1 rather than skipping if they are not). A new mix project brings its
own gate block here.

`mix sobelow` is in the root block and not substrate's: it armed
itself the moment `:phoenix` entered this project's dependency tree,
because `mix catapult.audit` carries a sleeper check for a Phoenix
surface with no security-focused static analysis (v5 §2.14), and it
names all three places arming it takes — the dep, a `qualityGates`
line, a ci.yml step. Substrate has no Phoenix and so no such line.
Its escape is `# sobelow_skip ["Check.Name"]` immediately above the
offending function, and it is only honored because `--skip` is on the
gate line — an annotation alone disarms nothing. `--ignore
Config.HTTPS` is scoped to a single finding rather than absorbed into
a `.sobelow-skips` baseline, for the reason `mix.exs`'s own
`ignore_advisories` gives: a silent gate re-blinds itself to the next
finding. Why it is ignored is recorded on the gate line itself, where
the edit would be made, and it is a settled decision rather than one
waiting on a condition: App Platform coerces HTTP to HTTPS at its
edge and offers no setting to stop it, so an endpoint `force_ssl:`
could only ever fire on the container-local health probe, which it
would answer with a 301 and fail the deploy. HSTS — the half the edge
does not supply — is set on `CatapultWeb.Router`'s `:browser`
pipeline, which `Config.HTTPS` cannot see because it reads endpoint
config.

The two blocks differ on one line only, and deliberately: the root's
`mix deps.audit` is an alias running `hex.audit` first and `mix_audit`
second (ORC-37), while substrate must not take an audit *dependency*
(`systems/substrate.md`), so there it is `mix hex.audit` on its own.

Every line in both blocks is armed in CI as of ORC-49 — `ci.yml`'s
`substrate suite` step carries the full set, and `qualityGates` runs
`mix catapult.audit.all` rather than the root-only task. So this block
is the local mirror of what CI runs, not the only thing running any of
it. The compile-connected line is v5 §2.14's second half (ORC-21); the
number's home is `pipeline.config.json` → `qualityGates` and `ci.yml`,
both author-owned by construction, which is what makes "raising it
needs a reviewed change" literal rather than aspirational and why a
ticket cannot arm or raise it (`docs/conventions.md` §2,
`systems/foundation.md`). It is `0` in both projects; every later value
is a concession.

Tests: no network, ever (fakes per conventions §9); `mix test`
creates/migrates `catapult_test` via the alias. `:live`-tagged tests
run only at milestone boundaries — never add one to the default
suite path.

## Load-bearing invariants (the ones agents trip on)

- Every component adopts `use Catapult.Component` and registers its
  claims; the composer fails the boot **and** the audit on collision.
- Public functions on a component's boundary use `defexport`
  (telemetry rides it; permissions will).
- No `DateTime.utc_now` in domain code (inject `Catapult.Clock`);
  no bare `name: __MODULE__` (register via `processes/0`); no
  unwrapped `Catapult.Config.Secret` inside a `Logger` call. The audit
  parses rather than greps (ORC-21), so a string that spells a ban is
  a string. The escape is a **comment** — `# catapult:allow <check>`,
  on the offending line or the comment line directly above it, and one
  written inside a string literal excuses nothing. A tag covering no
  violation is itself reported, so the escape list prunes itself.
- A `secret: true` config value comes back wrapped; `Catapult.Config
  .Secret.unwrap/1` at the call site is the only way to its contents,
  and it is meant to be visible in review.
- VM guardrails on `processes/0` are applied by the process, in
  `init/1`, via `Catapult.Guardrails.apply!/2` — the composer never
  threads them into a child spec, and the audit reports a guardrail
  declared and never applied. `max_heap_size:` is VM-enforced;
  `message_queue_alarm_len:` is sampled and reported, never enforced.
- An `errors/0` kind is built with the component's generated
  `use Catapult.Error` struct (`Engine.Error.new/2`), which is what
  makes the declaration the only vocabulary. The audit reports a kind
  declared and never constructed.
- An external application the plane calls is named in `lib/catapult.ex`
  `deps:` or the boundary compiler fails the build (the app list is in
  `mix.exs`). Pure Erlang applications cannot be restrained — that gap
  is `systems/foundation.md`'s and is deliberate, not forgotten.
- A **bundle-relative content path stays inside its own layer**.
  `Catapult.Dsl.Extends.resolve_content_path/2` expands both sides
  and refuses any candidate that escapes, so an escaping `prompt:`
  reads as "not found" rather than as a file. The value is
  bundle-authored, and a bundle is the customer's own content at the
  hosted tier — without the guard a `prompt:` of `"../.."` had the
  plane reading arbitrary files, which is not hypothetical: it was
  reproduced against `/etc/passwd` before being fixed.
- The plane makes no LLM calls and holds no working copies —
  generation is dispatched agent runs (conventions §11). A model
  call in plane code is an architecture violation.
- Root artifacts (supervisor, routers) are composed from component
  declarations, never hand-edited.
- The license split is load-bearing (`LICENSING.md`):
  `components/**` and `bundles/**` are Apache-2.0 and ship into
  generated projects — never copy plane code (AGPL) into them and
  never add a copyleft dependency there. New files take their
  directory's license.

## Where things actually run (the "why didn't that fire" list)

Each of these cost a wrong diagnosis before it was written down.

- **Agent runs have no BEAM.** `agent-design` and `agent-dev` install
  Go and nothing else (orchestration's `setup-pipeline`), because the
  pipeline is language-agnostic by design. `erlef/setup-beam` is a
  composite Action and unreachable from a shell string, so anything
  needing `mix` inside an agent job installs its own toolchain —
  which is the whole reason `bin/preview-build.sh` exists in that
  shape. **The gates do not run in agent jobs**; they run in `ci.yml`
  on the PR.
- **The pipeline audit only runs on ticket branches.** `ci.yml`'s
  `gate the pipeline audit` step greps the branch for `orc-[0-9]+`
  and skips the whole audit without one. So mutex, doc lint, class
  and design-ownership checks **never see an author branch** — a
  clean CI run on one is not evidence those checks passed.
- **A push made with `GITHUB_TOKEN` starts no workflow.** GitHub
  refuses to trigger on events created with it, so a job that commits
  back to a branch leaves the PR with *no* checks rather than
  failing ones. Orchestration's own action records this as its reason
  for publishing previews from the harness rather than a
  push-watcher. A push under ordinary credentials is what restores
  them.
- **The id/reasons audit does not see `docs/dsl/`.** Orchestration's
  check is scoped to `systems/` and `screens/`, so a rule in
  `bundle.md`, `chain.md` or `workflow.md` whose `.reasons.md` entry
  is missing or unamended passes the audit silently, and
  `pipeline reasons chain#22` does not resolve. The convention binds
  regardless — it is the contract's own rules that carry the ids —
  and the gap closes when that scope widens.
- **A stale `_build` fails `--warnings-as-errors` for a lie.** A
  half-finished compile leaves a dependency's modules missing, and
  the gate then reports them undefined at their call sites — which
  reads exactly like a real breakage in the caller. Before believing
  such a failure, `mix compile --force`; if it goes away, it was the
  build.

## Writing in the docs

- **State the rule; do not narrate what it replaced.** When a
  decision changes, the stale sentence is deleted rather than struck
  through and annotated with who corrected it and when — git holds
  that. This applies to `docs/*.md`, and `docs/v5-design-decisions.md`
  above all, since it is the design source of truth: it should read
  as the rules, not as their history.
- **The exception is the reason.** "X exists because Y went wrong" is
  load-bearing and stays — it is the thing that stops a later pass
  simplifying the rule back into the bug (`orchestration/CLAUDE.md`
  makes the same point about code comments). The distinction is
  between a rule's *rationale*, which is content, and a *changelog*,
  which is not.
- Corollary: a revision to a recorded decision belongs **in the
  document that records it**, not only in the system doc that
  noticed. Leaving the source of truth stating the superseded rule is
  how the next pass re-derives it.
- **A rule stated in more than one place is amended in every place,
  in the same change.** The retired v5 DSL spec stated each load-time
  rule at least twice by construction — §13's checklist and the §15.x
  section that owns it — and often a third time, in a worked example
  or §15.1's lifecycle mapping. Six consecutive design-review rounds
  each corrected one statement and left its siblings, so the same
  defect returned in a new place every round: §15.1's mapping against
  §15.2's worked example five times over (`merge`, the `reconcile`
  count, `checks`, the child lifecycle, `pending`), then §13's
  `critique`-adjacency amendment against both §15.5's own statement
  of that rule and §15.9's restatement of it — that last pair written
  by one pass, in one document, minutes apart. Grep the rule's own
  words before changing it: the second statement is rarely next to
  the first, and a worked example left behind by an amended rule is a
  load error nobody runs until dev.
- **The record is what the tree will be made to match, so a dev merge
  never falsifies it.** Design writes the system as it will be once
  dev implements it; if landing that implementation makes this record
  wrong, the design pass wrote the wrong thing. So it states the
  finished shape — the rule, a worked example that satisfies it, the
  mechanism as it will run — and never reports the tree's current
  state back at itself. Three forms of the same mistake, in
  increasing order of how easily they pass review: predicting a
  revision ("this passage is rewritten once X lands"); describing what
  is not built yet as though the record's job were to track build
  progress; and narrating the record's own scope ("not built as part
  of this pass", "whether that reverts is that diff's to settle, not
  this record's to predict"). The last is the one a pass reaches for
  when it has been told to stop doing the first, and it is the worst
  of the three: a disclaimer about what the document is declining to
  say carries no fact about the system at all. Where the tree has not
  caught up, that gap is the ticket's to carry, and an inline comment's
  in the file a reader would be misled by — never a sentence in the
  record whose life is shorter than the document's. The same reading
  catches the mirror image: a record describing a fix as landed because
  an earlier entry said it would. Check the tree, not the neighbouring
  entry.
- **A doc's claim about the tree is not evidence about the tree.**
  Of the "X is not built yet" sentences an audit of these docs
  checked, half described things that had shipped and half described
  real gaps — and nothing in the prose separated them. Check the tree
  before repeating such a sentence or building on it, and scope the
  check to where the thing would actually be: grepping
  `component.ex` for `__catapult_exports__` returns nothing and so
  "confirms" a stale doc, because the function is generated in
  `component/api.ex`.
- **A number in prose is a claim no later pass re-derives.** One
  milestone's design reviews caught eight, every one already read
  past by at least one pass: "four default-bundle gates" (five),
  "six shipped prompts" (five — the sixth was a file whose copy the
  same paragraph called inert), "three `checks`" (attributed to a
  worked example carrying two), "all four files" (five), "one of the
  two conclusions" (both), "9 call sites" (13), "index 3 … index 4"
  (matching no indexing the code uses), and "all three citations and
  the type" (three things, counted as four). One survived three
  passes, because each read the neighbouring sentence's figure
  instead of the tree. **Enumerate wherever the members are
  nameable**: "five shipped prompts (`vocab`, `ref`, `subcomparch`,
  `sysarch`, `comparch`)" is checkable in a way "six" is not, and the
  pass that has to add a member finds a list rather than a digit.
- **Naming some of the sites a rule reaches makes the next pass treat
  that list as all of them.** An entry named two dev-owned sites
  contradicting a rule it had just corrected; the dev pass fixed both
  and left a third, unnamed, stale in a file it had open. Name every
  site, or state the predicate that finds them — a partial list reads
  as a checklist rather than as an example.
- **A rule carries an id, and its reason lives beside the doc.** In
  `systems/*.md`, `screens/*.md` and `docs/dsl/*.md` every
  h2-or-deeper heading and every
  standing decision opens with an id — `#17` from the port or the
  author, `#ORC-247-2` from a ticket's design pass, which mints one
  above the highest it has minted in that doc, because two tickets
  designed against one doc from the same main both mint "the highest
  plus one"; the reason is `## <the same id>` in the doc's
  `.reasons.md` sibling (conventions §12, orchestration's DESIGN §4).
  Run `pipeline reasons delivery#17` before changing rule #17 of
  `systems/delivery.md`; amend the entry in the same commit; a new rule
  takes `<ticket>-<n>` (the author, a bare number one above the doc's
  highest bare id); a retired rule loses its
  line and its entry gains `retired:`. Cite a rule as `delivery#17` —
  the audit resolves the id and the wording is free to change. The
  record review is handed the entry behind every id a diff touches, and
  a rule changed against its reason with the entry unamended is a
  decline.
- **Cite by a registered shorthand or by path.** Two thirds of this
  repo's section citations name their document by a project shorthand
  — `v5 §7.8`, `conventions §2`, `chain.md` #22 —
  rather than by path. `pipeline.config.json`'s `citationShorthands`
  is what maps each to a file; an entry that cannot resolve in this
  tree (`DESIGN`, `orchestration`, `AGPL`) carries the reason on
  itself, so a later pass does not supply an invented path. Inventing
  a *new* shorthand means adding a key to that file, which is
  author-owned — a ticket cannot, so use one that exists or write the
  path.
