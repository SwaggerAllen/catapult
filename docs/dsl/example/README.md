---
paths:
  - docs/dsl/example/**
---

# The default pair, worked

`chain.yaml` and `workflow.yaml` are the platform's two default
bundles written out in full in the grammar `bundle.md`, `chain.md` and
`workflow.md` state: every tier, edge, flow and predicate on one side,
every type, gate and environment on the other. They are the worked
example the contract is read against, and the artifact `bundle.md`
#14's acceptance test measures.

The binding runs one way only: a workflow position names the chain
tiers that run at it, and the chain file names nothing in the workflow
(`bundle.md` #11).

`check.py` derives every tier's effective context from the edges,
resolves which type serves each flow, checks that the type's positions
cover the flow's tiers, runs the traversability rule over the
resulting order, and measures both files. Its output is quoted below
rather than restated, so every figure here is counted rather than
claimed. Run it from this directory; it is read-only and exits
non-zero on a load error.

## What lives in the schema, and what lives in the chain

`bundle.md` #10: a fact about one document lives in that document's
schema, and a fact relating two documents lives in the chain. Identity,
`draft.*` fields and plain cardinality are therefore schema
annotations, on the elements the loader already walks:

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
parent's fragments into the child at mint (`chain.md` #12). Those five
lines on each of `comp`, `subcomp`, `ui_subcomp` and `screen_subcomp`
are the only `fields:` in the chain.

## Effective context

The derivation (`chain.md` #20, #21): a tier reads its scope parent's
handle, and every edge instance whose source is the tier or its
parent, projected by the edge's `context:` (or the instance's own),
under the edge's name. The tier's `context:` map adds to that.
`check.py`'s output for three tiers:

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

`subcomparch` declares nothing: all three of its reads derive.

**Three cases the derivation has to answer, each of which cost a wrong
answer first.**

1. *Subtraction.* `feature_expansion → vocab` is a fan-out from the
   parent of `journeys`, `screens` and `requirements`, and none of
   them reads `vocab`; `sysarch` does read its parent's fan-out
   (`requirements → resp`). So `fanout` edges carry `context: none`
   and `sysarch` declares its `resp` read explicitly. `chain.md` #21's
   "adds and never removes" holds, at the cost of one explicit line.
2. *One instance needs its own projection and its own name.*
   `ui_coll → design_system` is a `dependency`-typed edge whose target
   has no fragments, so the instance carries `context: handle`; and it
   shares its source with `ui_coll → ui_coll`, so both would derive
   under the variable `dependency` and the second would overwrite the
   first. `check.py` did exactly that, silently, until the reads were
   compared walk by walk against the declarations. Hence: a derived
   read is named by its edge, and two instances of one edge from one
   source are a load error unless the second carries `as:`. Both
   instance-level `context:` and `as:` exist for this
   (`chain.md` #27).
3. *Reference instances that are citations, not reads.* `journey →
   screen`, `resp → journey`, `resp → screen` and `screen_coll →
   journey` are declared in a draft as citations of already-approved
   nodes, and the tree never walks them. They carry `context: none` on
   the instance. Without it, `screen_collarch` would derive a second
   read of the journeys it cites, alongside its explicit
   `all.journey`.

## Traversability

The rule, per flow and the type that serves it (`workflow.md` #23):
the type's positions list every tier active in that flow, each at
exactly one position; a structural read — a walk from self or the
parent — targets a node whose generating tier sits at the same or an
earlier position; a generation position none of whose tiers are active
in this flow is a warning. Join targets take their minting tier's
position; supplied tiers have none.

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
  note: feature_request -> delta: feature_request_plan reads all.comp, regenerated later
  ... (nine notes, one per plan tier per global read)
```

Structural reads are ordered strictly and global reads are noted only,
because a global read is of the project's approved state as of
dispatch and a plan tier reads the graph it is about to change. Every
plan tier reads `all.sysarch` and `all.comp`, both of which the same
ticket regenerates later at `architecture`; calling those ordering
errors is the mistake the first version of this check made. The
distinction is ORC-247 review 5's, drawn when it found that
`cascade_visit` targets never drain: the flow engine, not the loader,
owns what `all.<tier>` means inside a flow ticket.

Which type serves a flow is derived rather than named (`workflow.md`
#40): a flow whose schema delta is empty is a scaffold and a flow
carrying one is a change, so `scaffold` declares `serves: no_delta`
and `delta` declares `serves: has_delta`. A type may instead name
flows outright, and an outright claim beats a predicate; two outright
claims on one flow are a load error.

## Depth

A position's depth comes from the tiers it lists, never from a
declaration (`workflow.md` #28): a ticket stands at a position when
its own depth is at most the deepest tier there, generating where it
has a tier at its own depth and holding its children's branch where it
does not. A tier's depth is the number of ticket-spawning fan-outs
above it, and a fan-out spawns a ticket only where something generates
from the pool it mints (`chain.md` #42):

```
  ticket-spawning fan-outs: 6 of 13
     -> ['comp', 'screen_coll', 'screen_subcomp', 'subcomp', 'ui_coll', 'ui_subcomp']

     features               depths [0]  (own work at [0])
     experience             depths [0]  (own work at [0])
     requirements           depths [0]  (own work at [0])
     architecture           depths [0, 1, 2]  (own work at [0, 1, 2])
     implementation         depths [0, 1, 2]  (own work at [2])
```

The parenthesised column is what the position generates; the first is
who stands there. They differ at implementation, where every tier is
scoped to a subcomponent: a feature and a component hold the branch
their subcomponents' code merges into, so a gate and a PR are
available at all three granularities rather than only at the bottom.
The product positions stop at depth 0 because every fan-out there
mints a pool nobody generates from, so no ticket opens below them.

## The positions this workflow chooses

Five generation positions, each listing its tiers in `workflow.yaml`:
`features` (`feature_expansion`, `non_goals`, `vocab`), `experience`
(`journeys`, `screens`), `requirements` (`requirements`),
`architecture` (`sysarch`, `comparch`, `subcomparch`,
`frontend_sysarch`, `ui_collarch`, `ui_subcomparch`,
`screen_collarch`, `screen_subcomparch`) and `implementation`
(`impl_backend`, `impl_ui`, `impl_screen`). `delta` adds a plan
position before each, every one listing all five flow plan tiers.

Human gates follow `features`, `experience` and `architecture`; none
follows `requirements` or `implementation`, the latter per v5 §7.10's
touchpoint budget. This is the granularity a fixed status table cannot
express: an objection at `features-review` throws back to `features`
and does not touch `journeys` or `screens`.

Gates default to every depth (`workflow.md` #33). `delta` writes
`depth: 1` on its `engineering-review` citation — system and component
levels, with the reconciled branch covering the rest — and `scaffold`
leaves the default, because scaffolding reads the whole tree once.
Depth sits on the citation rather than the gate declaration precisely
because the two types cite one gate at two depths.

`scaffold` and `delta` each carry their own tier inventory, which is
what the binding's direction costs: the two lists hold 39 tier names
between them, 17 and 22. That standing charge is what makes a third
type something to justify by a difference in sequence rather than by a
difference in gates.

## Review and reconcile

`review: default` sits on all 17 reviewed tiers, one line each, and a
reader of the chain file sees which tiers are reviewed without listing
`prompts/review/` (`chain.md` #14).

`reconcile: default` sits on `sysarch`, `comparch`, `frontend_sysarch`,
`ui_collarch` and `screen_collarch` — the five fan-out tiers whose join
a human reads. A reconcile prompt is optional (`chain.md` #15): the
mechanical merge and the reconcile read happen either way, and the
block decides only whether the post-join gate shows an authored
document or the composed diff.

## Measurement

```
  chain.yaml: 455 lines (limit 800), 25 comment lines (5%)
  workflow.yaml: 182 lines (limit 240), 33 comment lines (18%)
```

The chain has room for roughly 300 further lines of comment under
`bundle.md` #14's bound, which is where a rule's reason goes when it
belongs beside the declaration rather than in the contract doc. The
thirty-minute reading half of that test is a human's to run.
