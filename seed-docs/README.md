# seed-docs — vendored upstream reference

Frozen source material from **SiegeEngine**, vendored so that agent
runs can read it. Nothing here is normative and nothing here is
maintained: it is the historical record the v5 design was drawn
against, kept verbatim.

Provenance: `github.com/SwaggerAllen/SiegeEngine` at
`5c7ad5a0e0c61b6168ccd4cd5c5e802acf6345bd`, copied
2026-08-18 without edits.

## Why this exists

Catapult's own documents cite this corpus and could not reach it.
`docs/dsl-syntax.md` and `systems/platform_content.md` both cite
"v5 §B.2" — that is **Appendix B of `catapult-spec-v4.md`**, in
this directory, not a section of `docs/v5-design-decisions.md`.
A design pass on ORC-7 discovered the gap the expensive way: asked
to port siege's prompt chain, it had no siege to read, authored the
bundle content fresh, and guessed at structure the v4 documents
state outright. That finding is what this directory answers.

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
inputs to a decision, not the decision. Four differences are known
and load-bearing, so that a reader does not mistake them for
oversights:

- **Responsibilities.** v4 §2 "A note on responsibilities" removed
  v3's `resp` tier and made responsibilities structured fields on
  the `requirements` body. **v5 restores `resp` as a tier** and
  hangs policy scoping off it (§4.5's "through responsibilities"
  grain). Read v4's collapse as the thing v5 reversed.
- **Domain/presentational and `fanin`.** v4 §1.9 and §4.3 build the
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
  for a `review_path:` to point at. The per-tier `review:` block
  (dsl-syntax.md §3) and the platform-wide review grammar
  (`<score>`, each `<finding id>` — v4 §B.3.2) carry forward
  unchanged; only the path concept is void.

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
