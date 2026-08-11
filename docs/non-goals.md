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
  may as well not think about it.")
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
  Debugging and observation only. The DAG is for machines; humans
  get Linear queues, PR diffs, and the docs site.
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
