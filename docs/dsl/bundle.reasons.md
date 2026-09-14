# bundle — reasons

The reason behind each rule in `docs/dsl/bundle.md`, keyed by the rule's id (conventions §12). Read one with `pipeline reasons bundle#n` before changing the rule it belongs to.

## #2

`Catapult.Dsl.Loader.load_axes/5` builds one chain from the `chain:`
field and there is no list form on purpose: a polyglot project still
has one document graph, with components in different languages
depending on each other across the boundary, so two chain bundles
would have no composition path back into one graph (v5 §5.5).
`catapult.yaml` is the loader's file rather than bundle content
because it is what the loader reads to find `bundles/` at all.

## #3

The one-file layout was never decided the first time; the per-file
tree carried 51 tier files with 600 lines of header comment and each
tier's name repeated in three paths. One file is what a newcomer
reads in one sitting, what a diff shows whole, and what a
modification UI edits in place rather than by creating and deleting
files. The path guard exists because a bundle is the customer's own
content at the hosted tier and a `prompt:` of `../..` was reproduced
reading `/etc/passwd` before the guard was added.

## #4

The workflow file names nothing outside itself because it declares
positions, gates and environments only; prompts, schemas and flows are
all chain content, and a workflow that reached for a file would be
reaching across the axis (#11).

## #5

`kind` is checked so a chain on the workflow axis fails at load rather
than at the first dispatch; unknown keys are refused so a misspelled
key cannot silently become a no-op; `extends:` is named explicitly as
refused because it is the one field a reader coming from a layered
system will reach for first (#7).

## #7

Git has a merge story and a load-time layer does not: a layer can only
replace whole files keyed on path, and divergence under it is
invisible, whereas a forked file shows in `git log` and a later
platform revision merges with a conflict exactly where both sides
touched the same lines (v5 §3.1, §6, §7.18).

## #8

Two mechanisms on purpose (v5 §9): forking is how content varies,
extensions are how vocabulary grows. Keeping code out of bundles is
what makes every load-time check possible and keeps the predicate
language non-Turing-complete, a property the scheduler and the audit
lean on rather than a style preference.

## #10

The split is by what a constraint ranges over. `minOccurs` on an
element, the identity attribute, and which elements are fields are
true of one document regardless of which chain uses the schema; a
`cardinality.when` that counts children by a field value, a
`declared_in` path that mints another tier, and a walk each relate two
nodes. Plain cardinality was stated in both places for the whole life
of the first grammar and only the schema's copy was ever enforced,
because the commit path validates against the XSD and nothing read the
DSL's rows.

## #11

The reference runs one way because a workflow naming a tier would
make the workflow specific to one chain's declarations, and a gate
declared on a tier would put organisation policy (who signs off, when)
into the document graph that v5 §7.16 keeps out of it. It is checked
strictly, not degraded, because the skeletons already stipulate
several positions of most shapes, so "fall back to the shape" has no
single position to fall back to; a misspelled `phase:` under a lenient
rule would silently run a tier at the wrong position.

## #12

v5 §7.19's reason for depth: a workflow's depth against a chain that
fans out less "applies at the levels that exist, silently. It must
*not* be a load error", because a workflow is meant to run over chains
of different shapes. A warning turns silent degradation into a visible
one without forking workflows per stack; an error would.

## #14

The community premise (v5 §8) is that a project customises its
bundle; "if customising requires learning YAML, that premise is
half-delivered". The redesign's first draft of the pair measured 466
and 137 lines; the
bound is the author's original estimate of 600 to 800 for the chain,
leaving room for the reasons a rule carries beside its declaration.
