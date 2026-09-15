# The prototype: both default bundles as one file each

README §5 step 4. `chain.yaml` and `workflow.yaml` are the default
pair hand-written in the grammar `../seam-decisions.md` §2 and §4
decide, from the tree at `main` plus what ORC-246 and ORC-247 landed
on their branches. The binding runs one way only: a workflow position
names the chain tiers that run at it, and the chain file names nothing
in the workflow. `check.py` derives every tier's effective context from
the edges, resolves which type serves each flow, runs the traversability
rule over the resulting order, and measures both files; its output is
quoted below rather than restated, so the numbers here are counted.

## What is in the files, and what moved out of them

**Into the schemas** (`../seam-decisions.md` §5's rule: a fact about
one document lives in its schema): identity, `draft.*` fields, and
plain cardinality. The schemas carry no annotations today, so this is
what two of them gain, shown on the elements the loader already walks:

```xml
<!-- sysarch.xsd: the element that mints `comp`, and the fields the
     comp handle exposes; `alias` is the identity ORC-246 chose -->
<xs:complexType name="Component">
  <xs:annotation><xs:appinfo>
    <catapult:mints tier="comp" identity="alias"/>
  </xs:appinfo></xs:annotation>
  <xs:sequence>
    <xs:element name="name" type="xs:string">
      <xs:annotation><xs:appinfo><catapult:field name="name"/></xs:appinfo></xs:annotation>
    </xs:element>
    <xs:element name="purpose" type="xs:string">
      <xs:annotation><xs:appinfo><catapult:field name="purpose"/></xs:appinfo></xs:annotation>
    </xs:element>
    ...
    <xs:element name="foundation" minOccurs="0" maxOccurs="1">
      <xs:annotation><xs:appinfo><catapult:field name="is_foundation"/></xs:appinfo></xs:annotation>
      <xs:complexType/>
    </xs:element>
  </xs:sequence>
  <xs:attribute name="alias" type="xs:string" use="required"/>
</xs:complexType>

<!-- comparch.xsd: a draft tier's own fields -->
<xs:element name="comparch">
  <xs:annotation><xs:appinfo><catapult:identity>id</catapult:identity></xs:appinfo></xs:annotation>
  <xs:complexType><xs:sequence>
    <xs:element name="technical-specification" type="xs:string"/>
    ...
    <xs:element name="subcomponents" type="Subcomponents">
      <xs:annotation><xs:appinfo><catapult:field name="decomposition_summary"/></xs:appinfo></xs:annotation>
    </xs:element>
```

What stays in `chain.yaml` because it relates two nodes: `produces`
(a draft path onto the parent), the edges' `declared_in`, the walks,
and the `mint.parent.*` fields on a join target, which copy the
parent's fragments into the child at mint. Those five lines on each
of `comp`, `subcomp`, `ui_subcomp` and `screen_subcomp` are the only
`fields:` left in the chain.

**Dropped from the tree's declarations:** `identity`, `fields` for
`draft.*` and `mint.<own>` paths, `handle` (default: every field plus
every produced kind), `draft` where it equals the derivation,
`generator: llm`, `prompt` where it equals the derivation, per-tier
`executor` (the `defaults:` block), `agent_step` and the `delivery:`
wrapper, the 17 review tiers (a `review:` line on the tier reviewed),
every plain `cardinality`, the four inline-form edge files, `scope:
reference`, the `synthesis` and `reference` generators, and the
`owner:` on every `produces` row.

## Effective context

The derivation: a tier reads its scope parent's handle, and every edge
instance whose source is the tier or its parent, projected by the
edge's `context:` (or the instance's own), under the edge's name. The
tier's `context:` map adds to that. `check.py`'s output for three
tiers:

```
-- comparch
   parent               self.parent.handle  (comp)   [derived]
   dependency           self.parent.dependency -> comp.handle.fragments[pubapi]   [derived]
   fulfills             self.parent.fulfills -> resp.handle   [derived]
   reference            self.reference -> ref.handle   [derived]
   failure_surfaces     self.parent.dependency -> comp.handle.fragments[failure_surface]   [explicit]
   binding_policies     self.parent.fulfills.policy_application~ -> sysarch_policy.handle   [explicit]
   citable_policies     all.sysarch_policy.handle   [explicit]
   non_goal_policies    all.non_goals_policy.handle   [explicit]
   vocab                all.vocab.handle   [explicit]
-- subcomparch
   parent               self.parent.handle  (subcomp)   [derived]
   dependency           self.parent.dependency -> subcomp.handle.fragments[pubapi]   [derived]
   reference            self.reference -> ref.handle   [derived]
-- screen_collarch
   parent               self.parent.handle  (screen_coll)   [derived]
   dependency           self.parent.dependency -> screen_coll.handle.fragments[pubapi]   [derived]
   calls                self.parent.calls -> comp.handle.fragments[pubapi]   [derived]
   renders              self.parent.renders -> ui_coll.handle.fragments[pubapi]   [derived]
   fulfills             self.parent.fulfills -> screen.handle   [derived]
   reference            self.reference -> ref.handle   [derived]
   failure_surfaces     self.parent.dependency -> screen_coll.handle.fragments[failure_surface]   [explicit]
   journeys             all.journey.handle   [explicit]
   vocab                all.vocab.handle   [explicit]
generating tiers 22: derived reads 43, explicit reads 42
```

Every one of the 100 context walks the tree's generating tiers
declare is present, derived or explicit, checked walk by walk against
the tree (the one exception is comparch's read of its own component's
structural policies, which ORC-247 retired: components do not see each
other's local policies). `subcomparch` declares nothing. Half the reads derive.
The seam pass said two thirds; that figure counted the 17 review
tiers' copies, which now derive through `review:` rather than through
the edges, and it counted the flows' 21 `plan_target` reads, which
here collapse to five list-valued instances.

**Three things the derivation met that the seam pass had not named.**

1. *A subtraction case exists.* `feature_expansion → vocab` is a
   fan-out from the parent of `journeys`, `screens` and
   `requirements`, and none of them reads `vocab`; `sysarch` does read
   its parent's fan-out (`requirements → resp`). So `fanout` edges
   carry `context: none` and `sysarch` declares its `resp` read
   explicitly. The rule "no subtraction, only addition" holds, at the
   cost of one explicit line.
2. *One instance needs its own projection and its own name.*
   `ui_coll → design_system` is a `dependency`-typed edge whose target
   has no fragments, so the instance carries `context: handle`; and it
   shares its source with `ui_coll → ui_coll`, so both would derive
   under the variable `dependency` and the second would overwrite the
   first, which the first run of `check.py` did silently and the
   walk-by-walk comparison against the tree caught. The instance
   carries `as: design_system`, and the rule is: a derived read is
   named by its edge, two instances of one edge from one source is a
   load error unless the second names itself. Instance-level
   `context:` and `as:` are therefore both part of the grammar.
3. *Reference instances that are citations, not reads.* `journey →
   screen`, `resp → journey`, `resp → screen` and `screen_coll →
   journey` are declared in a draft as citations of already-approved
   nodes; the tree never walks them. They carry `context: none` on the
   instance. Without that, `screen_collarch` would derive a second
   read of the journeys it cites, alongside its explicit `all.journey`.

## Traversability

The rule, per flow and the type that serves it: the type's positions
list every tier active in that flow, each at exactly one position; a
structural read (a walk from self or the parent) targets a node whose
generating tier sits at the same or an earlier position; a generation
position none of whose tiers are active in this flow is a warning. Join
targets take their minting tier's position; supplied tiers have none.

```
  type scaffold: 11 positions, 17 tiers listed
  type delta: 16 positions, 22 tiers listed

  seed -> scaffold: 17 tiers, positions unfilled: none (warning only)
  feature_request -> delta: 18 tiers, positions unfilled: none (warning only)
  refactor -> delta: 18 tiers, positions unfilled: none (warning only)
  bug_fix -> delta: 18 tiers, positions unfilled: none (warning only)
  downward_propagation -> delta: 18 tiers, positions unfilled: none (warning only)
  upward_propagation -> delta: 18 tiers, positions unfilled: none (warning only)
load errors: 0
  note: feature_request -> delta: feature_request_plan reads all.sysarch, regenerated later
  ... (nine notes, one per plan tier per global read)
```

Which type serves a flow is derived, not named: a flow whose schema
delta is empty is a scaffold and a flow carrying one is a change, so
`scaffold` declares `serves: no_delta` and `delta` declares `serves:
has_delta`. A type may instead name flows outright, and an outright
claim beats a predicate; two outright claims on one flow are a load
error.

**What the check found.** Every plan tier reads `all.sysarch` and
`all.comp` from the `plan` position, and both are regenerated later in
the same ticket at `architecture`. The first version of the check
called these ordering errors; they are not. A global read is of the
project's approved state as of dispatch, and a plan tier reads the
graph it is about to change. So the rule orders *structural* reads
strictly and notes global reads only, which is the same distinction
ORC-247's review 5 drew when it found that `cascade_visit` targets
never drain: the flow engine, not the loader, owns what `all.<tier>`
means inside a flow ticket. The reserved marker on `flows:` should
carry this note.

## The positions the default workflow chose

Declared in the workflow and listed with their tiers there. Five
generation positions: `features` (`feature_expansion`, `non_goals`,
`vocab`), `experience` (`journeys`, `screens`), `requirements`
(`requirements`), `architecture` (`sysarch`, `comparch`,
`subcomparch`, `frontend_sysarch`, `ui_collarch`, `ui_subcomparch`,
`screen_collarch`, `screen_subcomparch`) and `implementation`
(`impl_backend`, `impl_ui`, `impl_screen`). `delta` adds a plan
position before each, every one listing all five flow plan tiers.
Human gates after `features`, `experience` and `architecture`; none
after `requirements` or `implementation`, the latter per v5 §7.10's
touchpoint budget. This is the granularity the
fixed table could not express: an objection at `features-review`
throws back to `features` and does not touch `journeys` or `screens`.

Depth: gates default to every depth. `delta` writes `depth: 1` on
its `engineering-review` citation (system and component levels; the
reconciled branch covers the rest); `scaffold` leaves it at the default
because scaffolding reads the whole tree once. Depth therefore sits on
the citation, not the gate declaration, since the two types cite the
same gate at different depths.

## Costs the prototype makes visible

- **`scaffold` and `delta` are two types, and each carries its own
  tier inventory.** Decided by the author. The scaffold pass (v5
  §7.9) is reviewed at every depth, since it has no reviewed prior
  graph to trust; a change is reviewed at the system and component
  levels and catches the rest through the reconciled branch. Both
  types declare the same five generation positions with their
  critiques, and differ in `plan`, the staging environment, and the
  depth on `engineering-review`. The alternative, one type with the
  `[first, rest]` depth pair on its gates, was considered and
  rejected: it expresses this one case and no other without making
  the change flow depend on its parent container, whereas a type per
  kind of pass scales to any number of them. Flipping the binding
  prices the second type at its inventory as well as its positions:
  the two lists hold 39 tier names between them, 17 and 22. That is
  the flip's standing charge, and it is what makes a third type
  something to justify by a difference in sequence rather than in
  gates.
- **Join targets now say so.** `phase:` was the only key that marked a
  tier as generating, so with it gone the chain could not classify its
  own tiers without reading the workflow, which is the opposite of
  what the flip is for. The twelve join targets carry `draft: none`
  instead: twelve lines, and the classification is declared rather
  than inferred from which optional keys a tier happens to write.
- **`review: default` is written explicitly** on all 17 reviewed
  tiers, although A.2 allows deriving it from the existence of
  `prompts/review/<name>.md.liquid`. Written, because a reader of the
  chain file should see which tiers are reviewed without listing a
  directory; one line each.
- **`reconcile: default` names five prompts that do not exist yet**
  (`prompts/reconcile/<name>.md.liquid` for `sysarch`, `comparch`,
  `frontend_sysarch`, `ui_collarch`, `screen_collarch`). Under v5 4231
  a reconcile prompt is optional; the block is here to show its shape
  and where the default's fan-outs are.
- **The policy family and its edges are taken from ORC-247's design
  branch, not from `main`**: `sysarch_policy`, `comparch_policy`,
  `non_goals_policy`, five `policy_application` instances including
  the `<applies ref>` citation from `comparch`. The mint-time marker
  instances are written `declared_in: <tier>.mint.<marker>` to make
  the locus explicit; the tree writes `policy.structural`. Verify
  both against the ticket when it reopens.
- **`plan_target` instances take a list of targets**, five rows for
  the tree's twenty-one. That is a grammar addition (a list-valued
  `target:`) made because the twenty-one rows differ only in target.
- **No opening entry.** The tree's ticket types open with `pending`;
  with `pending` an engine flag, the first position is `plan` or
  `features` in the waiting state. `backlog` was not added, since the
  tree never used it and nothing here needs an author-balled entry
  before dispatch.
- **`labels: []` on every delta flow** is carried from the tree. With
  the flow no longer naming a type, the label is only the trigger that
  selects among flows, and whether it stays is the flow engine's
  question. The seed flow keeps no `ticket:` block at all.

## Measurement

```
  chain.yaml: 455 lines (limit 800), 25 comment lines (5%)
  workflow.yaml: 182 lines (limit 240), 33 comment lines (18%)
```

Against the tree: 2378 chain lines become 455, 286 workflow lines
become 182. The chain figure has room for roughly 300 lines of
comment before the limit, which is where a rule's reason goes once
the contract docs say which reasons belong beside the declaration
rather than in the doc. The thirty-minute reading test is the
author's to run.

## What the prototype could not test

Whether the derived variable names read well in the prompts: every
`self.parent.<edge>` read is now the variable `<edge>`, and the
prompts today use names the review-5 rewrite of ORC-247 was still
settling. The contract docs fix the naming; the prompt edits are
mechanical after that.
