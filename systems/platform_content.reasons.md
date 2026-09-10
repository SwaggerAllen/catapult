# platform_content — reasons

The reason behind each rule in `systems/platform_content.md`, keyed by the rule's id (orchestration's DESIGN §4). Read one with `pipeline reasons platform_content#n` before changing the rule it belongs to.

## #5

Somebody still has to supply the sane starting value, and that is this
layer's job rather than the check's — the elixir-target layer is what a
generated project's `mix.exs` comes from, and it is already where the
enforcement profiles live.

Nothing here exists yet: `bundles/` arrives in Phase 3 and the check lands
before it, so this is recorded now for the ticket that builds the layer
rather than built now. Until then the only project on the path is
`components/substrate`, which states its own list by hand because it is
not a generated project.

## #7

Catapult runs `check: [apps: [...]]` because `components/substrate` is a
**path** dep and Boundary drops a path dep's boundaries from its cached
view (`systems/foundation.md`, measured twice). A generated project
fetches substrate from hex like any other package, so the defect has no
purchase there and strict is simply available — and strict is the better
artifact: it needs no list, so it cannot have an incomplete one, and
`Catapult.Audit.BoundaryApps` is inert against it and says so on every
green run rather than auditing a declaration the project was never asked
to maintain. The plane's list is the exception that a defect bought, and
exceptions are not what a generator emits.

## #9

`seed-docs/README.md`'s second known delta replaces that whole mechanism
with v5 §4.1's product/backend/frontend split, which is a tier-level split
(product tier, frontend architecture tiers) rather than a `kind:`
attribute on a backend component — this chain, being backend-only, never
needs it; every component `sysarch` mints is simply a component.
`domain_parent`'s only job in v4 was letting a presentational comp read
its domain parents' fan-in synthesis — with no presentational kind and no
fan-in tier, that job has no successor to wire, so none is invented
speculatively; a frontend/product-side parent-link edge (if one turns out
to be needed) is Phase 5's decision when the frontend tiers it would serve
actually land, not this ticket's to guess at.

## #10

The `<kind>` decision test ("would deleting this component lose state or
business logic, or a way to expose them to outsiders?") and the
ownership-vocabulary self-check (watching for `persist`, `atomically`,
`commit`, `transaction`, `event log` leaking into a presentational
component's contract) both need two components in one graph with two
vocabularies — one owning state, one fronting it. This chain has only the
first, so the decision test has nothing to sort between and the leak check
has no other contract to have leaked from. Comparch's subcomponents are
not that split either: they divide on data/operation seams (writer,
reader, cache) that are all equally domain, so a subcomponent claiming
"commits atomically" is not borrowing someone else's ownership vocabulary
— there is no non-owning role for it to borrow from. A same-shaped check
built there would be a guess wearing a port's clothes, and the worry
underneath it — contract text making a claim it does not back — already
has stronger mechanisms in `comparch.md.liquid`: "Names create semantic
obligations" and the "Rationale, not inventory" final scan. What *did*
generalize is ported rather than dropped: the named anti-pattern list and
the wrong/right worked examples live in `sysarch.md.liquid`'s naming and
purpose rules, since a generic shell name and a purpose that parrots a
larger scope are failures any component can commit, backend or not. **The
`<owns>` block's un-fanned-out escape does not carry forward.** v4 let a
comp with no natural subcomponent split skip fanning out to subcomponents
entirely (impl attaching directly to the comp); expressing that as a scope
needs a union this ticket's closed scope-expression set (`singleton |
per(X) | child_of(X)`, dsl-syntax.md §3.1) has no form for (`per(subcomp)
OR per(comp where count(subcomponents)==0)`). Dropped as a content
simplification, not carried forward silently: `decomposition`'s
comparch→subcomp instance declares `source: {min: 1}`, making every comp
fan out into at least one subcomponent.

## #11

Separately, the worry this answers ("dropping it silently means the next
intake of the same raft proposes it again") does not arise: intake is one
function called at most once per project (`systems/delivery.md`'s ORC-107
entry), so there is no second intake of the same raft to re-propose from.

## #12

The raft may well argue for a responsibility- or component-scoped refusal,
not only a project-global one, but grains two and three
(`policy_application`'s policy→resp and policy→comp instances) need a
`resp` or `comp` id to scope through, and intake mints neither — nothing
has been decomposed yet when `non_goals` runs, by construction (it is a
chain root). A scoped refusal is real and expected; it enters the way v5
§1.1 already settles for every post-intake non-goal — as an ordinary
policy node via a ticket, once the `resp` or `comp` it scopes through
exists to reference. The same reasoning excludes the stub-grade attachment
§4.5 gives an "implementation-shaped" deferral (§2.16): that grade
attaches to a per-scope `<implementation>` block on a `comp`/`subcomp`
that, at intake, does not exist either. Nothing distilled at intake can be
implementation-shaped for the identical reason nothing distilled at intake
can be resp- or comp-scoped.

## #18

`prose` is what an absent grade already means operationally, a consistency
fact about the chain; the enforcement ladder above `prose` arrives with
its consumers, unrelated to distillation.

## #19

`comparch.yaml`'s own comment records why: `all.policy` is unfiltered by
construction (dsl-syntax.md §7.2) and would return every resp- and
comp-scoped policy too, indiscriminate noise next to the grains a tier
already reads explicitly. A scope-filtered "only the unscoped grain" read
has no expression in this DSL, and supplying one is a `core_dsl` question,
not bundle content; a consumer that wants `all.policy`'s indiscriminate
reading on its own merits (reconciliation, whose job is project-wide by
nature, is the plausible first taker) wires it against its own need.

## #21

Flow instance state becoming a real, checkable loader or engine concept is
what would reopen the two-stage split, on its own merits rather than under
a content port.

`feature_request`'s planning-tier prompt is
`seed-docs/siege-prompts/propose_feature.md`, ported close to verbatim
(real source, real content). The other four have no siege source — only
prose describes them, with no shipped prompt — so their planning-tier
prompts are authored fresh and kept proportionately small rather than
padded to match `feature_request`'s length.

## #24

This is the smallest stub that makes the reference resolve; the
elixir-target layer's real content (convention grammars, template tiers,
enforcement profiles) is a separate ticket's job. The platform-wide review
grammar (`schemas/review.xsd`) lives on this stub layer per this ticket's
own instruction — worth noting for a future reader that nothing in the
Phase 3 loader (`lib/catapult/dsl/chain.ex`) actually checks a
`draft.grammar` or `review.grammar` path resolves to a file at all yet
("prompt rendering, XSD body validation at commit" is this ticket's own
stated out-of-scope), so this placement is not load-bearing today — it is
the ticket-instructed shape, validated only as "does not break the
loader," not as "is read by anything yet."

## #26

**What this closes is silence, not a wrong number.** `critique` is opt-in
and an absent entry is not a load error, so a chain declaring none ships
its review tiers **inert** the moment the loader gains the form — nothing
red anywhere, and no signal that eight review tiers stopped running.

## #28

**It is a rule spanning two trees, which is why it is recorded here and
not only in the code.** `Catapult.Generation.ContextAssembly` omits
`feedback` on `[]` rather than emptying it, and a guard correct *only*
because of that promise is one plane-side refactor from silently opening —
a second renderer or a hand-built fixture would do it too. The plane keeps
the omission and the bundle guards independently, on purpose, and neither
half is redundant with the other. Each carries its own reason where it
would be edited: the templates' own `{% comment %}` blocks, and
`ContextAssembly`'s moduledoc. The Solid mechanics behind the spelling
live there too, including why a filter pipe is not available inside a
conditional under `Solid.parse/1`.
`test/catapult/generation/context_assembly _test.exs` holds the four
copies named above against all three shapes — these are the suite's claims
to keep current, not the next reader's to re-derive by reading
`deps/solid`.

A prompt's own top-level guard is not the working half either when nothing
behind it shows the feedback. The five prompts that carried one (`vocab`,
`ref`, `subcomparch`, `sysarch`, `comparch`) read `feedback` directly from
`ContextAssembly`'s own context rather than through the isolated partial,
so their `feedback.size > 0` guards fired — and then emitted static prose
("preserve everything the feedback doesn't ask you to change") without
ever interpolating `{{ feedback }}`, never showing the model what the
feedback said. A firing guard with nothing behind it is a second inert
copy that merely fails silently instead of failing loud.

That rule is the suite's to hold, not the next reader's to re-verify
against `deps/solid`. `context_assembly_test.exs`'s direct-render harness
(`Solid.parse/1` + `Solid.render/3` against the real
`bundles/default/prompts` tree, cited above) parses and renders the
partial file itself against the same populated shape it drives through the
guarded templates — `%{"feedback" => [%{"body" => "..."}]}`, string-keyed
because that is what Solid resolves against — asserting the `{% for entry
in feedback %}` loop renders each entry's fields. That is the coverage a
bare `{{ feedback }}` would fail, which is what makes the spelling above a
checked rule rather than a remembered one.

**What this does not close.** Even with the feedback text visible,
"preserve every alias, dep edge and policy the feedback doesn't touch,
verbatim" — the tier-specific content `sysarch`, `comparch` and
`subcomparch` keep — asks the model to round-trip a body it is never
shown: `draft` stays off-limits to a generation tier's own prompt, so
nothing here gives the model a baseline to preserve *against*. The gap
stayed masked as long as the guards never printed the feedback that would
have made someone notice, and closing it for real means either admitting
`draft` to a generation tier's prompt specifically when it is regenerating
over feedback — narrowing, not repealing, §9's "review-tier alone" rule —
or replacing the verbatim-preservation instruction with something
achievable without it. It is a standing-invariant question spanning
`dsl-syntax.md` §9/§3.3, `systems/generation.md`'s own restatement of the
same rule, and this doc, not a call-convention fix — named here rather
than silently carried forward as unenforceable prompt text.

## #29

With none of `partials/_architecture_framing`'s thirteen call sites across
`bundles/default/{prompts,flows}/**` passing any, `feedback` never entered
its scope and its `{% if feedback.size > 0 %}` block never fired, on any
tier or flow — an inert guard masking two live defects, not a hook waiting
on a future caller. `draft` never enters that scope either way: it is
generation-prompt-off-limits by `dsl-syntax.md` §9's own design
(`Catapult.Generation.ContextAssembly.build_variables/5` sets it only for
a review tier's own dispatch), and every one of the thirteen call sites is
a generation tier.

## #30

Passing `feedback` through unmodified to a bare `{{ feedback }}` — `{%
render "partials/_architecture_framing", feedback: feedback %}` and its
fellow twelve, with the interpolation left as written — would not have
started rendering the comment text either. `feedback` is a list of maps
(`body`/`locator`/`author_id`/`posted_at`); Solid's list-stringify path
flattens and `Enum.join`s, which calls `to_string` per element, and a bare
Elixir map has no `String.Chars` implementation — verified directly
against `deps/solid`: `{{ feedback }}` on a non-empty list raises
`Protocol.UndefinedError`, not a wrong rendering. So the
straightforward-looking fix (pass the variable, leave the interpolation as
written) would have turned "the model never sees feedback" into
"generation crashes the first time any node carries feedback" — a
regression the partial's dead guard was accidentally shielding against.

## #31

The partial opens "You are reviewing the draft below," and all eight
`review/<tier>.md.liquid` prompts render it as a bare `{% render
"partials/_review_framing" %}`. Bare `{% render %}` isolates scope, so
`draft` never entered the partial and the draft was never below anything:
every review dispatch in the chain asked a model to judge an artifact it
was not shown. `Catapult.Generation.ContextAssembly.build_variables/5`
does supply `draft`, and only to a review tier's own dispatch — the
variable was present at the call site and dropped at the boundary, which
is why nothing failed loudly.

## #33

The write path builds findings atom-keyed
(`Catapult.Generation.CommitPath`'s own `review_findings/1`) and
`feedback_variable/3` converts by hand for exactly that reason, two
functions above `prior_review_variable/3`, which does not. It does not
need to: the column is `{:array, :map}`, so the value crosses jsonb, and
`%{id: "f1"}` reads back `%{"id" => "f1"}` — the atom key is unreachable
and `entry.id` resolves. The store round trip performs the conversion the
sibling function performs explicitly, which is why the asymmetry between
them is not the bug it looks like.

## #36

This is also why `screens` cannot be `child_of(journey)`: a screen
legitimately named by more than one journey's walk (`v5 §4.2`'s "screen
belongs to 0..n journeys") would mint as two different nodes under a
per-journey fanout, one per referencing journey. `screens` being
`per(feature_expansion)` and authoring every screen (journey-driven and
standalone alike) in the one pass that already sees every journey is what
keeps the pool deduplicated without inventing any mint-time merge the
loader doesn't have.

## #40

This makes the hybrid case native rather than special, as v5 §4.1
requires: a raft with prose and no mocks omits the variable and reads as a
prose-only raft; a raft with mocks and no prose has `project_doc` omitted
instead and `feature_expansion` still runs, extracting from mock evidence
alone.

## #41

No tier depends on rendering a prototype, because no generation run can
promise one: the chain's generation runs dispatch into the target project
via `catapult-dispatch.yml` (`test/catapult/generation/fixtures
/catapult-dispatch.yml`), whose steps are fixed and carry no
project-toolchain step at all — mint an OIDC token, check out the bound
repo, fetch the rendered context, `npm install -g
@anthropic-ai/claude-code`, run the agent, report the result. The one
install it makes is the agent's own; it never resolves the target
project's dependencies and never starts a dev server, and the dispatch
contract offers no place to ask it to. A mock set needing `npm install &&
npm run dev` to be legible is read as whatever static source it contains,
the same as one that's already static markup. No runnable-target
convention exists for a generation run to use, so every mock set is read
as source.

## #43

An invented state or an `<implicit/>` feature is ordinary content in
`screens_review`/`feature_expansion`'s own review the same as any other
row; being chain-proposed rather than mock-evidenced changes nothing about
what a reviewer checks, and `screens`' review checklist already reads the
whole state list for exactly this (above). A second, dedicated pass over
content the ordinary review already reads would be checking a thing
already checked, not adding coverage.

## #45

`all.sysarch.handle` is what makes reading the backend sysarch handle
expressible at all: `sysarch` is `scope: per(requirements)`, a sibling of
`frontend_sysarch` under no common fanout edge, so there is no
`self.parent` walk between them — `all.<tier>` is exactly the mechanism
this loader ships for a needed read with no walkable relationship, not a
workaround.

## #46

`drained?(comp)` (`systems/engine.md`'s ORC-235 entry) reduces to
`sysarch` `:approved` for the same reason `comp`'s handle fields do, so
this read costs `frontend_sysarch` no wait beyond what
`all.sysarch.handle` already requires of it.

## #49

Two guarantees stack, not one: first, no edge instance anywhere in this
bundle names a UI-family tier as `source` and a screen-family tier as
`target` — the bundle simply carries no such site, so nothing downstream
can walk that direction — and second, were a future bundle edit to add one
anyway (mistakenly or not), the full-graph acyclicity check would refuse
the *load* over it, because `screen_coll → ui_coll` (`renders`, below)
already exists in the same graph and the two together are a cycle at the
tier level. `v5` §5.1's "inexpressible" claim holds on both counts: absent
by construction, and rejected by the loader if that ever stops being true.

## #50

This walk has the identical self-referential shape — `ui_collarch` reads
`self.parent.dependency -> design_system.handle`, an edge only its own
draft declares — but unlike `renders`/`uses_shapes`/`calls`, no
tier-ordering benefit is available to relocate it for: `design_system` is
pinned at intake (v5 §1.1) and carries no draft of its own to wait on, so
nothing about *when* the edge is declared changes whether the content
behind it is settled. The walk resolves through the instance's own
locators (`docs/dsl-syntax.md` §4.2, `systems/core_dsl.md`'s ORC-236
entry): `source_ref: self.parent` names `ui_coll` (`ui_collarch` is
`per(ui_coll)`) and `design_system` being `scope: singleton` needs no
`target_ref:` at all, so this instance extracts and resolves with no
explicit locator — a same-tier locator pair, since the edge's own `{min:
0, max: 1}` cardinality is a fact about *this* `ui_coll`'s dependency,
which a project-wide pool read can't carry.

## #51

A UI or screen collection fulfills no `resp`, so the
through-responsibility grain has nothing to scope through — a direct
collection-to-policy link would be speculative surface with no cited need
behind it. A future ticket needing component-collection policy scoping
makes that case against its own cited need.

## #52

None is needed: `fulfills`' `screen_coll → screen` instance and
`reference`'s `screen_coll → journey` instance already give the screen
family everything `domain_parent` was for — a link from an architecture
node to the product-side surface it implements — and the UI family, having
no product-tier counterpart of its own to link to, needs no such edge at
all. No replacement edge is minted.

## #54

No entry in `pipeline.config.json` names or needs to name this convention:
the file has no label-mapping section for either axis, mutex labels here
resolve straight off `systems/*.md`/`screens/*.md` file maps, and nothing
about a *generated project's* own future label scheme touches that file at
all.

## #56

`fulfills.yaml`'s `screen_coll → screen` instance is the case that makes
the distinction load-bearing: `screen_coll` is a join-target tier with no
`draft:` of its own (v5 §5.3), so the "hosts" relationship it names is
declared inside `frontend_sysarch`'s draft instead, the tier that mints
`screen_coll` in the first place — the path's leading segment is
`frontend_sysarch`, and that is the schema a correctness check has to
read, not one `screen_coll` will never have.

## #57

**Five stale paths in the `catapult-test` fixture repo, harmless but worth
naming.** `ToySeed.reset_files/0` pushes each stub to
`.catapult-stub/<root_tag>.xml`, so the five affected stubs land at the
hyphenated paths (`.catapult-stub/frontend-sysarch.xml` and so on);
`reset_repo/2` overwrites the paths it names and deletes nothing
(`systems/delivery.md`'s ORC-228 entry), so the five old underscored paths
stay in the fixture repo indefinitely. Harmless — the dispatch harness
reads the path the context response names, not a directory listing — but a
reader of that repo should know the five underscored `.catapult-stub`
entries are dead.

## #64

`core_dsl#45`'s own reason entry has the mechanism — why `identity_value/2`
resolved to `nil` on all five, and the uniqueness argument for `alias` over
each tier's own display text. This entry is the narrower, content-side
fact: which schema element each of the five tiers' alias lands on, and why
`screen` is the one tier that splits off rather than taking the value the
other four take.

`policy` mints from three drafts into one pool — `sysarch.xsd`'s `Policy`,
`comparch.xsd`'s own separate `Policy` complexType, and `non_goals.xsd`'s
`Candidate` — so it is three schema sites for one tier, not one. `vocab`,
`resp` and `journey` are each a single site (`feature_expansion.xsd`'s
`Term`, `requirements.xsd`'s `Responsibility`, `journeys.xsd`'s `Journey`).
Six sites, five tiers.

`journey`'s alias has a second consumer already declared in the bundle:
`screens.draft.screen[].journeys.journey[].@ref` and
`screen_collarch.draft.journeys.journey[].@ref` both cite a journey by
`<journey ref="...">`'s free-text argument sentence today, and that same
attribute gets a stable value the moment `<journey>` carries an `alias`, at
no extra cost.

`screen` is not grouped with the other four because its mint element never
carried a `<name>` in the first place — `screens.xsd` was authored against
`slug` as the tier's identity from the start (v5 §2.1, "the slug spine";
`bundles/default/prompts/screens.md.liquid:128`, "**`<slug>` is the
spine**"), not a tier that happened to lose a `<name>` element some other
tier kept.
