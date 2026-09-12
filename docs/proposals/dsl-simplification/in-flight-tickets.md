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

## ORC-247 — a policy can only be applied by the draft that mints it

**Status:** Designing, sixth pass, after a "Ready for redesign" bounce
at review 5. Branch carries design-owned docs only (ten files, +832
/ −164); dev's half is unimplemented. Two record-review declines and
one harness "blocked" notice along the way.

**Kind:** mixed. The bundle-content half is an exception: problem 2
(a `sysarch` policy carrying `<structural/>` names a comp target
nothing can resolve) is the fourth mint-locus × marker combination a
draft can produce, and ORC-246's `generation#53` cannot hold without
it. The grammar half is the parking case: three new load rules, one
new grammar form still unsettled at round 5, and a rewrite of how
walks bind to prompt variables. This ticket is the growth-in-content-
tickets pattern happening during the evaluation itself.

### What it decided, after five rounds

Filed as two content problems in the `policy` grain: applying a
policy required minting it (so a component fulfilling a `sysarch`
policy verbatim re-mints a duplicate), and a `sysarch`-minted
structural policy has no resolvable comp target. The decisions, in
the order the reviews forced them:

- **Pass 1.** `<structural/>` retires from `sysarch.xsd`; a project-
  level policy is `<required>` or neither. `comparch.xsd` gains
  `<applies ref="...">` inside `<policies>`, extracted the ordinary
  reference way (`source_ref: "@ref"`, `target_ref: self.parent`) as
  a further `policy_application` instance. An edge may therefore mix
  mint-time-marker instances and ordinary-locator instances
  (`core_dsl#39` amended, `dsl-syntax.md` §4.2).
- **Review 2, author decision: components do not see each other's
  local policies.** The citable set is project-level (`sysarch`) and
  non-goals-distilled only. A `ref` names whatever the target tier
  declares as identity, which is `nil` for every policy until ORC-246
  lands `alias`; the citation route is inert until then.
- **Review 3, author decision: no tier is minted by more than one
  parent tier, enforced at load.** Found because adding `all.policy
  .handle` to comparch's context is a permanent readiness deadlock:
  `policy` has three fanout drivers including `comparch`, and
  `drained?(policy)` needs every comparch approved, itself included.
  The flat pool with three mint loci (platform_content#15, v5 §4.5)
  becomes a tier *family*: `sysarch_policy`, `comparch_policy`,
  `non_goals_policy`. `policy_application` grows to five instances
  (a `comparch_policy → resp` required instance is newly needed or
  comparch `<required>` policies lose their edge after the split);
  `child_of(X)` is single-sourced (`core_dsl#45`); `all.<tier>` is
  refused when the reader is in the target's driver closure
  (`core_dsl#46`); synthesis tiers go from ten to twelve.
- **Review 4, author decision: per-entry prompt-variable naming lands
  in this ticket.** comparch must read `all.sysarch_policy` (citable)
  and `fulfills.policy_application~ -> sysarch_policy` (already
  binding) as two variables, and §9's rule merges every walk with the
  same target tier into one. So a `context:` entry may be `{<walk>:
  <name>}` giving the walk an `as:` name; entries merge by shared
  name, never by tier; a name colliding with `self`/`feedback`/
  `prior_review`/`draft`/`raft` or shared across target tiers is a
  load error (`core_dsl#47`). Review 5 then found the same defect
  already shipped: **eighteen sites** (nine tiers and their nine
  reviews) where distinct reads of one tier fuse into one variable,
  six of them `self.parent.handle` fused with a dependency read
  (`platform_content#65`, still being enumerated).
- **Review 5 (open):** name all eighteen sites; settle the `as:` form
  (single-key map versus an explicit `{walk:, as:}` pair); specify
  `as:` on `input.*` entries; fold `cascade_visit` targets into `#46`
  as a third never-drains case.

Rule ids on the branch: `core_dsl#45`/`#46`/`#47` new, `#17`/`#39`
amended; `generation#52` new, `#8` amended; `platform_content#64`/
`#65` new, `#11`/`#15`/`#17`/`#19`/`#45`/`#48` amended; `engine#18`/
`#21`/`#22` amended; v5 §4.5 amended. `generation#52` and
`platform_content#64` collide with ORC-246's ids; under PR #161's
scheme both tickets re-mint as `#ORC-246-n`/`#ORC-247-n` on reopen.

### What it says about the seam

- **The walk-to-variable binding is grammar, and it was mechanism.**
  §9's "one variable per target tier, same-tier walks merge" is an
  engine convenience that silently fused distinct reads in nine tiers,
  and no review saw it until round 5 of an unrelated ticket. `seam-
  pass.md` entry 7 called the walks the DSL's core and said keep them
  intact. That stands, with one amendment: how a walk is named in the
  prompt is part of the walk's grammar, not a derivation. The
  prototype should try `context:` as a *map* from variable name to
  walk (or list of walks): naming becomes mandatory and explicit, the
  merge rule disappears (a name with two walks merges by
  construction), `#47`'s cross-tier and reserved-name errors reduce to
  key uniqueness plus a short reserved list, and the `as:` form
  question dissolves. That is one fewer rule than the branch carries
  and it closes the eighteen-site defect class by shape.
- **"One parent tier per tier" is the engine's requirement under its
  readiness model, and the record should say so.** `drained?` is per
  tier, so a pool with several drivers cannot be safely read with
  `all.<tier>` by any of them. The alternative was per-instance
  readiness in the engine; the grammar constraint was cheaper. Entry
  2 and entry 4 gain this as a stated constraint with its reason, and
  the flat-pool intent (v5 §4.5's three grains) survives as a family
  of same-shaped tiers. Worth noting for the prototype: three
  identical synthesis tiers is the review-tier shape again, and a
  single-file chain can express "this tier, minted by each of these
  parents" without three files if the loader treats the family as
  one declaration with three drivers. That is the engine-side
  alternative in disguise; whether it is worth building is the
  author's call, and either answer needs the readiness rule stated.
- **`@ref` is a second use of the attribute locator.** Entry 5 argued
  `@from`/`@to` could be a convention rather than a declared
  `source_ref`. `<applies ref>` is a citation row whose attribute
  names the source; the same convention (a row's `ref` attribute
  names the far end) covers it. The `@attr` locator still has no
  case a convention does not.
- **`cascade_visit` targets never drain.** Review 5's fourth finding
  is a reserved construct (flows) interacting with a live rule
  (`#46`). The reserved marker should carry exactly this kind of
  note: which live rules the construct already touches.
- **Growth pattern, live.** A content bug became five rounds, three
  load rules, one grammar form, one semantics rewrite and a tier
  split, with two record-review declines for narrating rounds. Each
  step was locally right. README §2.5 is describing this ticket.

### Where it lands in the plan

| Decision | Plan home |
|---|---|
| `<structural/>` retires from `sysarch`; `<applies ref>` on `comparch`; five `policy_application` instances; three `decomposition` retargets; prompt edits | bundle content; carried into the prototype |
| Policy tier family (`sysarch_policy`, `comparch_policy`, `non_goals_policy`) | bundle content, forced by `#45`; prototype tests whether a family declaration expresses it in one place |
| `child_of(X)` single-sourced (`#45`) | chain contract, live, with the readiness reason stated; `seam-pass.md` entries 2 and 4 |
| `all.<tier>` refused in the driver closure (`#46`), `cascade_visit` as a never-drains case | chain contract, live; the flows reserved entry cites it |
| Per-entry variable naming (`#47`, `as:` form open) | chain contract, live; `seam-pass.md` entry 7 amended; prototype tries `context:` as a name → walk map, which supersedes the `as:` form question |
| Merge-by-name semantics (§9) | dissolves under the map form; otherwise chain contract, live |
| Eighteen fused-variable sites (`#65`) | bundle content; the prototype names every walk, so the list is the prototype's diff |
| Mixed marker/locator instances on one edge (`#39`) | chain contract, live; entry 4 (instance is the unit) already covers it |
| v5 §4.5 amendments | record; unchanged by the redesign |
| `generation#52` (extraction gate widens to `policy_application`), `edge_type_atom/1` clause | generation record and engine code; not DSL |

### To reopen against the new grammar

Two tickets, not one. The content half (structural retires, `applies`
citation, the policy family, prompts, extraction gate) reopens
against the prototype's bundle and is dev work with a settled design.
The grammar half (`#45`, `#46`, `#47`, the §9 rewrite) does not
reopen as a ticket at all: it is input to the redesign's chain
contract, where the rules are written once with their reasons, and
the prototype settles the `as:` form by choosing the map shape or
not. The eighteen collision sites are then the prototype's own diff
rather than a list to maintain by hand.
