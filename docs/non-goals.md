# Catapult — confirmed non-goals

The negative space, recorded with reasons (v5 §1.1's doctrine, eaten
by us first). Proposing one of these is not forbidden — but per
orchestration's rule, do it knowing you are arguing against a
recorded decision, and say so explicitly.

- **No self-bootstrap.** Catapult is not built from its own doc
  graph; orchestration delivers it (v5 §1.3). Reasons: the
  self-modification crash risk (a bad deploy bricking the tool that
  fixes it), the size mismatch (Catapult is smaller than its target
  class, so self-hosting proves little), and the historical fact
  that the byte-identity bootstrap requirement is much of why v4
  never shipped. The sane residue: Catapult consumes the shared
  components as an ordinary library user.
- **No absorption of existing codebases.** Projects enter as fresh
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
- **No workflow interpreter in the DSL, no bundle-side code, no
  Turing-complete predicates** (v5 §6, §7.10, §9). The plane's
  Commanded aggregates are the semantics; declarations configure
  them. Extensions are platform-shipped. This is a correctness
  property the scheduler, audit, and security posture lean on.
- **No per-project protocol restructuring** (v5 §7.10). Projects
  bind tracker ids and tune marked thresholds; states and gates are
  platform-fixed, because prompts, plane logic, and shared
  vocabulary are all written against them.
- **No tracker product.** Linear is the working UI, behind the
  Tracker port. The tell that would reopen this: catching ourselves
  teaching Linear state (custom fields carrying doc-graph data,
  load-bearing prose parsing). Until then, the port keeps the exit
  cheap and we build zero tracker UI.
- **No dashboard-as-working-surface** (v5 §7.4, systems/dashboard.md).
  Debugging and observation only, *for the work loop* — artifact
  review and ticket action live in Linear and PRs. Settings and
  onboarding (the bindings UI, v5 §7.10) and the configuration
  surface (a composer that files graph-state changes as PRs — it
  never bypasses a gate) are ops and authoring-composition, not the
  work loop, and are explicitly in-bounds.
- **Catapult never executes target-project code** (v4 §A.10.5
  carried forward, sharpened): agent runs execute code in their own
  CI/runner environments; the plane dispatches and observes but
  never runs generated code in-process. The plane's blast radius is
  its own.
- **No multi-writer projects.** One driving author per project;
  collaborators read. The coordination model for concurrent human
  writers is a different system (v4 §A.0.1 commitment 4, still
  true in v5).
- **No experimentation/percentage-rollout flag machinery** (v5
  §2.10): release flags, ops kill-switches, actor targeting — no
  more. Machinery without a customer at this scale.
- **No LiveView/React mixing within one frontend target** (v5 §1.4):
  one product tier, one stack per target.
- **No hand-maintained inventories**: no code inventory in systems
  docs (the code is the inventory), no hand-written permission
  matrices, no hand-written API docs where generation exists.
  Documents that mirror code drift silently; every such document is
  generated or absent.
- **No second home for the reference instance's live facts.** App
  name, region, public hostname, port, autodeploy, the migrate
  PRE_DEPLOY job: `SETUP.md` §2 records them and nothing else
  restates them. The README says the deployment exists, that
  `/health` is the only served path, and points at §2 — nobody
  opens a README to find a database cluster name, so the one home
  is the file a reader is already in when the values matter.
  (Author decision, ORC-40.) This is the entry above one level up
  rather than a case of it: that rule is scoped to documents
  mirroring *code*, and these are prose facts about a running
  system, but the failure mode is identical and we have first-hand
  evidence. ORC-2's README paragraph (`4a4aa91`) sourced the
  deployment to `.do/app.yaml` one commit after `b5c878f` deleted
  that file — the same paragraph, in its first week, citing
  something that no longer existed. The next drift is a hostname or
  a port, which a reader acts on. Corollary, and the reason no
  check is added: **no doc-lint holding the two files in
  agreement.** A lint is what a second copy needs; one home needs
  nothing, and these facts leave the tree entirely at
  open-sourcing, so the lint would be written to be deleted.
  **Amended (ORC-29): the public hostname's home moves, it does not
  multiply.** The live suite has to dereference that value and prose
  cannot be dereferenced, so the hostname becomes
  `config/test.exs`'s `:live_base_url` and §2 names the key where it
  used to print the URL. Every other fact in §2 stays put. The
  amendment is faithful to the reason rather than the letter: what
  ORC-40 was written about is a stale copy nobody checks — a README
  paragraph citing a file deleted one commit earlier — and a
  hostname the live suite reads at every boundary is checked by
  machine once a milestone, going red and naming itself when it
  drifts. Prose never had that property. The rule the amendment
  keeps: still one home, and a fact acquiring a code consumer moves
  to where code can read it rather than getting a copy there.
- **No vendored, pinned or freshness-checked copy of the advisory
  database** (ORC-37). The obvious repair for `mix deps.audit`'s
  fail-open — clone `mirego/elixir-security-advisories` ourselves,
  assert it is non-empty and recent, fail the build otherwise — makes
  us the maintainer of a fork of someone else's mirror of the GitHub
  Advisory Database, with its refresh cadence as our build's
  liveness dependency. The gate is bought far more cheaply by
  sourcing the signal from Hex, which cannot report clean from a
  fetch it did not make. Revisit condition: Hex's advisory feed
  proving materially behind the GitHub database in practice, which
  would be an argument for a real second source rather than for
  babysitting this one.
- **No `mix_audit` dependency in `components/substrate/`** (ORC-37).
  Substrate is Apache-2.0 and ships into every generated project, so
  each dependency it declares is one imposed on trees we don't own.
  `mix hex.audit` is built into Hex and covers substrate's lockfile
  for free; adding a package to obtain a weaker second opinion spends
  other people's dependency budget to do it.
- **No removal of `mix deps.audit` now that Hex covers the gate**
  (ORC-37). Demoted is not deleted: it reads the GitHub Advisory
  Database, which is a genuinely different source, and it earned its
  place the day it armed by catching the postgrex advisory and
  forcing the series bump (ORC-3). Two sources disagreeing is the
  condition this ticket made legible, not a defect to resolve by
  dropping one until the Hex feed is shown to dominate it.
- **No `:live` tag on a test that doesn't cross a real network
  boundary to a real external system** (ORC-29). The tag buys a seat
  in the once-per-milestone suite and nothing else, so a `:live`
  test that exercises the health plug in-process — or over a
  listener this same job started — reproduces the empty gate this
  ticket was filed about, one level in, and worse: `no-tests` at
  least says nothing was checked, where a green run over a local
  fixture claims the world was. If a test needs no deployed thing,
  it belongs in the default suite, where its determinism is an asset
  instead of a disguise.
- **No `test/live/` directory** (ORC-29). Live tests sit beside the
  system they exercise, under that system's file map, and the tag
  alone decides the cadence. A directory is a second axis that can
  disagree with the first, and one directory holding every system's
  live tests would give a single file map a veto over every system's
  tickets — the mutex collision the maps exist to prevent.
- **No polling or retry-until-deployed in the live suite** (ORC-29).
  Deploy detection is the plane's job and already exists (poll the
  App Platform API, compare SHAs). A live check that waits out a
  rollout is a second, slower deploy detector, and its long timeout
  is exactly where a real outage hides. A bounded per-request
  timeout is the whole budget.
- **No asserting the deployed SHA equals this checkout's** (ORC-29).
  Autodeploy fires on the merge to main and the boundary run follows
  within minutes, so equality races the rollout and produces a flake
  — and a flaky boundary signal costs more than the coverage it
  would buy, which is the failure mode ORC-29 exists to stop. Assert
  the SHA is stamped (not the `"dev"` fallback), which catches the
  real defect — an image that never went through the build path —
  without racing anything.
- **No argv-sniffing in the `test` alias** (ORC-29). The tempting
  version notices `--only live` and skips `ecto.create`/
  `ecto.migrate` so the live-suite job needs no database, saving an
  author-owned workflow edit. Rejected: that alias is what makes
  `mix test` correct for every other run in the repo, and a version
  that drops migrations on the strength of a flag fails silently and
  in the one direction that matters — a suite passing against a
  stale schema. The job gets CI's environment instead; the edit is
  cheap and it is visible.
