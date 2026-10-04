# seed-docs — vendored upstream reference

Frozen source material from **SiegeEngine**, vendored so that agent
runs can read it. Nothing here is normative and nothing here is
maintained: it is the historical record the v5 design was drawn
against, kept verbatim.

Provenance: `github.com/SwaggerAllen/SiegeEngine` at
`5c7ad5a0e0c61b6168ccd4cd5c5e802acf6345bd`, copied
2026-08-18 without edits.

## Why this exists

Design passes need this corpus and could not reach it. A design pass
on ORC-7 discovered the gap the expensive way: asked to port siege's
prompt chain, it had no siege to read, authored the bundle content
fresh, and guessed at structure these documents state outright. That
finding is what this directory answers.

Catapult's own docs and code do **not** cite it. They are written to
be read without it: a v4 section number in `docs/**`, `systems/**`,
`bundles/**` or `lib/**` is a defect, not a reference. This
directory is for the reader porting more of siege, not for the
reader understanding Catapult.

## Contents

| Path | What it is |
| --- | --- |
| `catapult-spec-v4.md` | The v4 platform spec. **Appendix B** is the siege→catapult port mapping: tier set, edge instances, fragment kinds, per-tier prompts, grammars, readiness predicates, phase rules. |
| `catapult-default-bundle-v4.md` | The v4 default bundle reference — one section per tier, pinning scope, identity, handle, body grammar and generator. The most directly useful document here. |
| `catapult-default-bundle-v4-examples.md` | Worked examples for the above. |
| `siege-prompts/` | SiegeEngine's shipped prompt chain, verbatim: generation, `review_*` and `modify_*` prompts per tier. |

## How to read it against v5

**Where these documents and `docs/v5-design-decisions.md` disagree,
v5 wins** — that is the whole point of there being a v5. These are
inputs to a decision, not the decision. Four differences are
conceptual; three more are structural, and those three will cost a
reader a load error rather than a misconception, so they're kept
separate below. All seven are known and load-bearing, so that a
reader does not mistake them for oversights:

### Conceptual differences

- **Responsibilities.** `seed-docs/catapult-default-bundle-v4.md`
  §2's "A note on responsibilities" removed
  v3's `resp` tier and made responsibilities structured fields on
  the `requirements` body. **v5 restores `resp` as a tier** and
  hangs policy scoping off it (§4.5's "through responsibilities"
  grain). Read v4's collapse as the thing v5 reversed.
- **Domain/presentational and `fanin`.**
  `seed-docs/catapult-default-bundle-v4.md` §1.9 and §4.3 build the
  presentational surface out of domain fan-in synthesis. **v5 §4.1
  replaces that whole mechanism** with the three-way product /
  backend / frontend split. `fanin`, `domain_parent` and the
  `kind: domain | presentational` attribute are v4 machinery that
  v5 does not carry forward.
- **The product tier.** v4 starts at `feature_expansion` →
  `requirements`. v5 §4.1 inserts `journeys` and `screens` between
  them. The v4 chain head is not superseded — it is extended.
- **`review_path:` is not carried forward.** v4's per-tier grammars
  and prompts assume review is a distinct pass whose own output lands
  somewhere the chain can name. `docs/v5-design-decisions.md` §7.19
  (landed after `catapult-spec-v4.md` §B.2 was drawn against) makes a
  tier's auto-review a **system status and agent step**, run as a
  second dispatched agent reading the PR's already-committed state,
  producing **comments, not a committed artifact** — there is nothing
  for a `review_path:` to point at. Per-tier review (`chain.md` #14 —
  a `review:` block on the tier it reviews, not v4's nested block) and
  the platform-wide review grammar (`<score>`, each `<finding id>` —
  `seed-docs/catapult-spec-v4.md` §B.3.2) carry forward unchanged;
  only the path concept is void.

### Structural differences

These three are not disagreements about what the system should do —
they're places the v4 examples name a file or a shape that the merged
v5 loader (`Catapult.Dsl.Manifest`, `Catapult.Dsl.PredicatesFile`)
does not read. A reader who copies the worked example gets a load
error, not a design question.

- **`predicates.yaml`'s wrapper key.** `catapult-default-bundle-v4-examples.md`'s
  worked example (line 374) opens with a top-level `predicates:` key
  and nests the named predicates under it. `Catapult.Dsl.PredicatesFile`
  reads the file's own top-level map as `{name => expression}`
  directly — there is no wrapper. ORC-84's dev pass hit this as a real
  load failure (`predicates.yaml's predicate "predicates" is %{...},
  expected a string expression` — the whole map parsed as one
  predicate) and removed the wrapper. The file itself is still a
  separate file in v5, which makes this the easiest of the three to
  miss: only its contents changed shape, not its existence.
- **`fragments.yaml` as a separate file.** The layout tree (line 47)
  and the bundle.yaml example (line 147, `fragments: fragments.yaml`)
  name it as its own registry file. `Catapult.Dsl.Manifest` reads
  `fragments:` as a plain inline list of kind names inside
  `bundle.yaml` (`@chain_keys` has no pointer form), and nothing
  anywhere parses a standalone `fragments.yaml`. Also recorded in
  `bundles/default/bundle.yaml`'s own comment, `systems/platform_content.md`,
  and `docs/non-goals.md`.
- **`plan.yaml` has no parser and nothing to declare.** The layout
  tree (line 26) and bundle.yaml example (line 149, `plan_rule:
  plan.yaml`) both name it. v5 §6 drops the phase machinery entirely
  — no `phased:` tiers, no phase-plan projection, no plan rule — and
  `bundle.md` #3's bundle layout does not list it.

## Licensing

**Settled: pulling from this corpus into `bundles/**` is authorized,
including verbatim.** SiegeEngine is AGPL-3.0 and `bundles/**` is
Apache-2.0 (`LICENSING.md`), which would normally be a one-way door.
It isn't one here: SiegeEngine has a **single copyright holder, no
third-party contributors, and has never had a user other than its
author**, so there is no recipient with standing under AGPL §13 or
anything else, and a sole copyright holder may license their own work
under whatever terms they choose. The repo goes private before
Catapult publishes. Checked and clean: no file under
`siege-prompts/` carries third-party attribution.

So the license is **not** a reason to avoid carrying text across, and
was briefly recorded as one in error. The reason ORC-7 authors fresh
anyway is structural — v5 moved the tiers the prompts are written
against — plus a standing author preference for rewriting over
porting. Both are about quality, not permission.

One thing worth keeping: if siege text does land in `bundles/**`
close to verbatim, say so in the commit message. Not a license
requirement — just so a later reader who recognizes the prose knows
it was deliberate and authorized rather than a leak across the zone
boundary.
