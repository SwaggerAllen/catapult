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
inputs to a decision, not the decision. Three differences are known
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

## Licensing

SiegeEngine is AGPL-3.0, and this directory sits in Catapult's
AGPL-3.0 zone (`LICENSING.md`: "everything else"), so vendoring it
here changes nothing. **The constraint is downstream:** `bundles/**`
is Apache-2.0 and ships into customer projects, so prompt text may
not be copied from `siege-prompts/` into a bundle. Both repos share
a copyright holder, so this is a housekeeping rule rather than a
legal risk — but the Apache-2.0 zone stays clean by construction,
which is why ORC-7 authors bundle content fresh with these
documents as reference rather than porting bytes.
