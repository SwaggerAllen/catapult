# Catapult — confirmed non-goals

The negative space, recorded with reasons (v5 §1.1's doctrine, eaten
by us first). Proposing one of these is not forbidden — but per
orchestration's rule, do it knowing you are arguing against a
recorded decision, and say so explicitly.

**Schema** (orchestration's `nonasks` parser). One entry per `## `
heading; `scope:` is the line immediately under it — a blank line
between them makes it prose and the entry silently goes universal.
Scopes are the mutex labels, comma-separated, or `universal`. Everything
above the first heading is preamble and is never inlined into a prompt,
so this note is free. Name every system a refusal touches rather than
the closest one: an extra name costs a pass one paragraph, a missing one
hides the refusal from the pass that would have broken it.

**What belongs here, and what does not.** A refusal about exactly one
system is a standing decision of that system and lives in its
`systems/*.md`, beside the decision it qualifies — where the pass that
could violate it is already reading, and where it cannot drift from the
positive rule it is the negative half of. This file holds the two kinds
that have no such home: refusals every pass must see, and refusals that
span systems, which a per-doc home could only serve by being copied
into each one. That is the whole of the scope line's job. Entries are
still never deleted by a pass; relocating one is an author move, and
the citations that pointed here move with it.
**What keeps this file finite.** A refusal earns an entry only as the
negative half of a rule stated somewhere positive — never on its own,
and never as a record that some pass considered an approach and
declined it. The set of approaches a design could rule out is
unbounded; the set of rules it actually has is not, so entries are
counted against rules rather than against passes. A pass that checks
its change against an entry and finds the entry already answers it has
nothing to add: the entry answering it *is* the outcome, and appending
a paragraph saying so is how a bounded list stops being one.

## No per-project restructuring of the *automation* protocol
scope: universal

(v5 §7.10, §7.16). Projects bind tracker ids and tune marked
thresholds; the agent and queue states, and the graph connecting
them, are platform-fixed, because prompts, plane logic and shared
vocabulary are all written against them. We fix the shape of the
automation, not the shape of the organization.

**The admission rule: a state may be declared iff no plane logic
branches on it.** Review states qualify — their only job is routing a
human, nothing dispatches from one, and no prompt is written against
one — so they are declared, vary by ticket type, and default to a UX
review and an engineering review (§7.16). A work-item type's own
existence and the gate array it declares qualify the same way
(`docs/dsl-syntax.md` §15.2), as does where in that array a gate sits
(§15.3) and whether adjacent entries are grouped into a bare sub-array
(§15.10). What stays refused is a project rewiring the automation graph
itself.

## No second home for the reference instance's live facts
scope: universal

App name, region, public hostname, port, autodeploy, how the
deploy migrates: `SETUP.md` §2 records them and nothing else restates
them. The README says the deployment exists, that `/health` is the
only served path, and points at §2 — nobody opens a README to find a
database cluster name, so the one home is the file a reader is already
in when the values matter. (Author decision, ORC-40.)

**The measurement this exists because of:** ORC-2's README paragraph
(`4a4aa91`) sourced the deployment to `.do/app.yaml` one commit after
`b5c878f` deleted that file — the same paragraph, in its first week,
citing something that no longer existed. The next drift is a hostname
or a port, which a reader acts on. Corollary, and the reason no check
is added: **no doc-lint holding two files in agreement.** A lint is
what a second copy needs; one home needs nothing.

**A fact acquiring a code consumer moves rather than multiplies**
(ORC-29). The live suite must dereference the public hostname and
prose cannot be dereferenced, so it lives in `config/test.exs`'s
`:live_base_url` and §2 names the key instead of printing the URL.
Still one home.

## No self-bootstrap
scope: universal

Catapult is not built from its own doc
graph; orchestration delivers it (v5 §1.3). Reasons: the
self-modification crash risk (a bad deploy bricking the tool that
fixes it), the size mismatch (Catapult is smaller than its target
class, so self-hosting proves little), and the historical fact
that the byte-identity bootstrap requirement is much of why v4
never shipped. The sane residue: Catapult consumes the shared
components as an ordinary library user.

**Narrower than it sounds — a documentation-only proof does not trip
this.** Phase 5's exit criterion (`docs/build-plan.md`'s Phase 5
section) scaffolds a reviewed architecture chain from a small seed
written for the purpose: intake through the architecture chain only,
stopping at reviewed documents, with no code generated, no delivery,
and no redeploy of Catapult from the result. That tests the intake
and architecture-chain machinery end to end; it is not the
self-hosting this entry refuses, which is building and *running*
Catapult from its own graph: this entry's refusal is about execution,
not about what a raft describes.

## No absorption of existing codebases
scope: universal

Projects enter as fresh
scaffolds; documentation and tracker history seed the feature set;
code is regenerated. The platform's structure is narrow by design
and existing apps won't conform to it; an absorption mode is a
different product. (Author decision, Polyphony conversation.
Revisit condition: none foreseeable soon — "so far out of scope we
may as well not think about it.") Boundary sharpened at the mocks
pass: user-supplied mocks and design systems enter as **seed
evidence and pinned artifacts** (v5 §4.1, §5.4) — read, rendered,
designed against, never absorbed; business logic still
regenerates.

## No workflow interpreter in the DSL, no bundle-side code, no Turing-complete predicates
scope: system:core_dsl, system:platform_content

(v5 §6, §7.10, §9). The plane's
Commanded aggregates are the semantics; declarations configure
them. Extensions are platform-shipped. This is a correctness
property the scheduler, audit, and security posture lean on.

## No inbound write path from a mirrored tracker
scope: system:delivery, system:dashboard

(v5 §7.17) — the
live half of the entry above. Mirroring outward is a read model
leaving the building and is safe by construction. Accepting
arbitrary state changes back in reintroduces unmapped states,
last-write-wins and unattributable writes into a system that just
escaped them. Anything inbound is a §7.1 signal, validated like any
other, never a state change adopted on the tracker's word.

## Catapult never executes target-project code
scope: universal

(carried forward, sharpened): agent runs execute code in their own
CI/runner environments; the plane dispatches and observes but
never runs generated code in-process. The plane's blast radius is
its own.

## No concurrent authoring of artifact bodies
scope: system:engine, system:dashboard

(v5 §7.16).
Narrowed, deliberately, from a former `No multi-writer projects`
entry — **small teams are supported**, and that entry contradicted
both §1's target class ("single-author / small teams") and §2.9's
identity component, which ships orgs, membership, invitations and
roles-as-data. It was inherited rather
than decided here, and the narrowing is a reconciliation, not a
reversal. What remains out is what v4 actually carved out: two
people editing the same artifact body under merge semantics the
plane would have to invent. Bodies live in git, PRs already carry
those semantics, and the plane does not grow a second set.
Concurrent *action on the delivery protocol* — several people
holding a sign-off role, racing each other on transitions — is in,
and is optimistic concurrency (§7.16): first writer wins, a stale
`from` is rejected rather than applied.

## No experimentation/percentage-rollout flag machinery
scope: system:substrate, system:platform_content

(v5
§2.10): release flags, ops kill-switches, actor targeting — no
more. Machinery without a customer at this scale.

## No LiveView/React mixing within one frontend target
scope: system:client_ts, system:platform_content

(v5 §1.4):
one product tier, one stack per target.

## No per-language chain bundle splitting
scope: system:core_dsl, system:platform_content

A polyglot project still has one document graph — a component in one
language depends on and is depended on by components in another, so
they must load as one bundle. This is forced by the loader at its
root: `catapult.yaml`'s `chain:` field names exactly one bundle, and
`Catapult.Dsl.Loader.load_axes/5` builds exactly one chain per project
from it — no list — so two independently authored chain bundles, one
per language, have no way to merge into a single project's graph.
Per-platform variation lives inside the one chain bundle's own
architecture and implementation prompts, never as a second bundle
merged in — there is no bundle-layering mechanism left to merge one
through (`dsl-syntax.md` §11, v5 §5.5).

## No hand-maintained inventories
scope: universal

: no code inventory in systems
docs (the code is the inventory), no hand-written permission
matrices, no hand-written API docs where generation exists.
Documents that mirror code drift silently; every such document is
generated or absent.
