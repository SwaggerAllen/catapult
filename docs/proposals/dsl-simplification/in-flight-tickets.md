# In-flight tickets folded into the plan

Two tickets were in design when this proposal was written, both
touching the DSL. Both stay open until the pipeline restarts; the
replacement tickets are cut against the new grammar then. This file
records what each ticket decided, so the intent survives whichever
way the tickets are closed, and where each decision lands in the
plan. Sources: the Linear threads (design passes and reviews, several
rounds each) and the landed diffs on each ticket's branch against
`main` at `bdfd150`.

The classification used below is README §5 step 2's: **live**,
**reserved**, **questioned**; plus **exception** for a ticket that
fixes a live defect and should land regardless of the freeze (the
rule in the sequencing discussion: a ticket whose consumer revealed
what the grammar needed is an input to the classification, not noise
on top of it).

## ORC-246 — the live walk stalls at `ui_collarch` and `screen_collarch`

**Status:** Design review, round 5. Branch carries design-owned docs
only; dev's half (fixtures, tests, six schema edits, five prompt
edits, one loader edit) is unimplemented.

**Kind:** exception. The chain cannot run to completion without it
(live run 29 stalled at 22 of 34 tiers). Let it land.

### What it decided, after five rounds

The ticket as filed was fixture and test coverage: two toy-seed
fixtures fail their own XSD because ORC-235 moved elements out of the
grammars and not out of the fixtures; nothing checked conformance
offline; `feature_expansion.xml` mints no `vocab`; `frontend_sysarch
.xml` has none of the content ORC-235 relocated into it. Those became
`generation#52` (fixture conformance is a default-suite assertion
keyed by the `@root_tag_fixtures` map) and `generation#53` (the
raft's content mints an instance of every edge and node a
dispatchable draft can produce).

The DSL change fell out of round 3, when the review found #53
unachievable: five tiers (`vocab`, `resp`, `policy`, `journey`,
`screen`) declared `identity: id` while their mint elements carried
neither an `id` nor an `alias` attribute, so every one minted with a
`nil` scope key. Two author decisions followed:

- Round 3: widen the identity vocabulary rather than rename
  `<slug>` or add a redundant attribute, because `slug` is already
  `screen`'s load-bearing identity everywhere else (the `screen:<slug>`
  mutex label, `journeys.xsd`'s `<screen slug="...">` reference).
- Round 4, superseding half of round 3: every fanout-minted element
  carries an `alias` attribute the authoring prompt instructs and
  constrains, rather than reading identity off a display name. The
  review's uniqueness table is the reason: `resp`'s name is
  enforced-unique, `vocab`'s explicitly is not (a project-level and a
  feature-local term may share a name), `policy` mints from three
  drafts into one pool with no stated uniqueness, `journey` states
  none. `screen` alone keeps `slug`.

Landed as three rules: `core_dsl#45` (vocabulary widens to `id |
alias | name | slug`; one line in `dsl-syntax.md` §3's comment),
`platform_content#64` (four tiers declare `identity: alias` and gain
a required `alias` attribute at six schema sites, the same regex and
uniqueness instruction `<component>` already carries; `screen`
declares `identity: slug`), and the `generation#53` paragraph tying
them together.

### What it says about the seam

- **A blanket default hid a real defect.** Every tier in the bundle
  declared `identity: id`, "this bundle's blanket default, inherited
  rather than chosen" (platform_content#64's own words). Six tiers
  resolved only through a hardcoded `alias` fallback in
  `identity_value/2`; five resolved to nothing, and no load check
  could see it because the identity value is draft content. This cuts
  against `seam-pass.md` entry 1's suggestion to default `identity`
  away: a default that is wrong for a third of the tiers is worse
  than a required field. The better move is entry 19's: identity is a
  fact about the *mint element* (which attribute is the key), and the
  XSD is where that element lives. Whether it is declared there
  (`xs:appinfo`) or on the tier, it should be chosen per tier, never
  defaulted.
- **Uniqueness of identity values is projection-time.** The review
  placed it with cardinality counts on §13's projection-time side: a
  draft's own identity values are content, not bundle. That is a
  contract/mechanism boundary the new chain doc should state once.
- **The consumer revealed the grammar.** Nothing in the spec was
  wrong about `identity:`; the value set was simply never exercised.
  The first tier to *use* the vocabulary found the defect. This is
  the ORC-232/235/236 pattern again and the reason reserved
  constructs carry a marker.
- **Fixture coverage is a chain-shape invariant.** `#52`/`#53` are
  generation rules, but their premise is "every tier and edge the
  bundle declares has something to mint from in the raft". A
  single-file chain makes that enumerable from one place; the drift
  guard (README §5 step 7) should include it.

### Where it lands in the plan

| Decision | Plan home |
|---|---|
| `identity:` set is `id \| alias \| name \| slug` | chain contract, live; carried into the target grammar as-is |
| Identity is chosen per tier from the mint element's key | `seam-pass.md` entries 1 and 19: amend entry 1 (no default for `identity`), settle placement in the prototype |
| Identity-value uniqueness is projection-time | chain contract, one sentence at the contract/mechanism boundary |
| `alias` attribute on six mint elements, prompt instruction | bundle content; carried into the prototype's schemas unchanged |
| `#52`/`#53` fixture rules | generation record, not DSL; the drift guard cites them |

### To reopen against the new grammar

Dev's half is unchanged by the redesign: fixture and schema edits,
the conformance assertion, the offline walk over the frontend five.
Only `tier.ex`'s `@identities` line and the `dsl-syntax.md` comment
move, to wherever the new chain contract declares the set. The
reopened ticket cites `core_dsl#45` and `platform_content#64` by id;
the redesign keeps both ids.
