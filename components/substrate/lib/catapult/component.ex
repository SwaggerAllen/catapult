defmodule Catapult.Component do
  @moduledoc """
  The component behaviour (conventions §4): every Catapult component
  adopts it and declares its claims on shared root resources through
  the registry callbacks. The root composer (`Catapult.Component.Composer`)
  aggregates all components and fails on collision — a warning about a
  name collision is a collision that ships.

  Registered names ride the slug spine (conventions §3): a component
  slugged `:engine` claims `engine:*` topics, `:engine_*` queues,
  `[:catapult, :engine, ...]` telemetry, and nothing else.

  ## The roster is one table

  The shape, opts vocabulary, spine rule and collision key of every
  name-claiming registry live in `Catapult.Component.Registries`, one row
  each; the callbacks below are the documented contract, and their empty
  defaults are generated from that table. What a registry *means* is
  here; what it *is* is a row.

  ## Mechanism before consumers

  Most of the roster aggregates into nothing today, and that is the
  point (systems/substrate.md): retrofitting a registry once its
  consumers exist means editing every component, while a registry
  aggregating into nothing costs a table row. `mix catapult.audit`
  prints a census on every green run so an unconsumed registry stays a
  fact somebody sees.

  ## No optional callbacks

  Every callback keeps an overridable empty default and none is
  `@optional_callbacks`. Incremental adoption is what the default
  already buys; optional callbacks buy the same thing and charge the
  composer a `function_exported?/3` guard at every call site, so an
  aggregation that is total becomes one that can silently skip a
  component.
  """

  alias Catapult.Component.Registries

  @type placement :: :local | :singleton | :sharded
  @type distribution :: :distributed | :service | :internal
  @type audience :: :internal | :public | :partner
  @type classification :: :none | :operational | :customer_content | :personal
  @type verb :: :get | :post | :put | :patch | :delete

  @doc "The component's slug — the spine every derived name hangs off."
  @callback slug() :: atom()

  @doc """
  Config surface: env-var specs, prefixed by the slug.

  Honored by `Catapult.Config`, which is where the opts vocabulary
  (`cast:`, `default:`, `required:`, `secret:`, `external:`) is
  documented. Declared names are claimed names: the composer fails the
  build on two components binding one variable, and on a name off the
  slug spine that does not say `external: true`.

  One of two registries outside the roster table: it is the only one
  with a boot half, and its error messages are worth their specificity.
  """
  @callback config() :: [Catapult.Config.declaration()]

  @doc """
  How this component reaches the people who use it, and under what
  terms: `[distribution: t:distribution/0, license: "SPDX-Id"]`.

  Both opts are required and there is no default class. A default would
  make every project's audit print a policy verdict nobody asserted,
  which is the shape `mix catapult.audit`'s license check exists to
  remove from the ladder (docs/non-goals.md); the pair also cannot be
  half-defaulted, since there is no license a component "probably"
  carries. An undeclared component is reported by the audit alongside
  every other structural absence — never at compile time, because the
  overridable empty default keeps `use Catapult.Component` sufficient to
  compile, exactly as `errors/0`'s required `remedy:` does.

  One callback rather than two, because the facts are only meaningful as
  a pair: a license says nothing about obligation until you know who
  receives the code, and a class says nothing about terms. Two callbacks
  would also manufacture two half-declared states that mean nothing and
  have to be reported anyway.

  The second registry outside the roster table, and for `config/0`'s
  reason plus one of its own: it claims no name. Two components
  declaring `Apache-2.0` is the ordinary case rather than a collision,
  so the table's `:claim` and `:identity` columns — the reason it exists
  — would sit empty (`Catapult.Component.Registries`).

  The composer validates the *shape*; the policy — which classes are
  checked, against which identifiers — is `Catapult.Audit.License`'s
  alone. A production node refusing to start because a transitive
  dependency's license string is unrecognized is a catastrophic response
  to a question with no runtime consequence whatsoever (`LICENSING.md`).
  """
  @callback licensing() :: [{:distribution, distribution()} | {:license, String.t()}]

  @doc """
  PubSub topic prefixes claimed (as atoms; rendered `slug:name`).

  The one claimed name with no spine check, and the exception proves the
  rule: the composer renders the prefix from the slug, so demanding one
  in the atom would be the slug written twice.
  """
  @callback pubsub_topics() :: [atom()]

  @doc """
  Oban queue names claimed, `queue` or `{queue, opts}`.

  Opts: `cron:` — periodic schedules, declared on the queue they run on
  so that what runs on a timer is diffable rather than buried in plugin
  config (v5 §2.2). A list of `{schedule, worker}` pairs, because a
  crontab entry points at a worker and never at a queue
  (`Oban.Plugins.Cron`): a single string could say *when* but never
  *what*, and one queue hosting two periodic jobs could not be spelled at
  all. The composer checks the pairing back — a scheduled worker whose
  own `queue:` is not the entry it was declared under is a job that will
  run somewhere nobody declared.

  Most queues have no schedule, so the bare atom stays the spelling a
  diff shows:

      def oban_queues do
        [:engine_work, {:engine_nightly, cron: [{"0 3 * * *", Engine.SweepWorker}]}]
      end
  """
  @callback oban_queues() :: [atom() | {atom(), keyword()}]

  @doc "Telemetry event names claimed (each `[:catapult, slug | rest]`)."
  @callback telemetry_events() :: [[atom()]]

  @doc """
  Event types with their versions, `{type, version}` (conventions §6).

  There is no bare form and no default version: an unversioned event is
  precisely the state v5 §2.4's upcasting discipline exists to prevent,
  and a default of `1` would make the first version the one fact
  invisible in the diff — the version every later upcaster is written
  against.

  The claimed name is the type, so two components declaring one type
  collide, while one component declaring the same type at two versions
  is ordinary and permanent: old shapes live as long as the log does.
  """
  @callback events() :: [{atom(), pos_integer()}]

  @doc """
  Named processes with declared placement (conventions §5), with
  optional VM guardrails: `{name, placement}` or
  `{name, placement, opts}`.

  Opts, and the two are not one grade (ORC-21):

    * `max_heap_size:` — a real BEAM process flag. The VM kills a runaway
      process before it takes the node down (v5 §2.5), which is
      `runtime`-grade enforcement for the cost of a registry field and
      legal precisely because processes are never the state of record.
    * `message_queue_alarm_len:` — a threshold observability *samples and
      reports*, not a bound anything enforces. There is no per-process
      message-queue flag in the VM, and the node-global facility that
      exists is notify-only and singular; the name states the grade,
      because `max_` would be a promise the platform cannot keep
      (`Catapult.Guardrails`, `systems/observability.md`).

  Guardrails are applied by the process, in `init/1`, via
  `Catapult.Guardrails.apply!/2` — never threaded into a child spec by
  the composer, which would need the option conventions of start
  functions it did not write. `mix catapult.audit` reports a guardrail
  declared and never applied.

  Most processes have no guardrail, so the two-element entry stays the
  spelling a diff shows.
  """
  @callback processes() :: [{atom(), placement()} | {atom(), placement(), keyword()}]

  @doc """
  The component's deliberate failure vocabulary at its boundary
  (v5 §2.2): `{kind, meaning, opts}`, spine-prefixed kinds each with a
  one-line meaning.

  Opts: `remedy:` — required prose, "what to do about it"; `runbook:`
  and `admin:` ride alongside as promotions. The ladder promotes by
  adding, never by replacing: a graded remedy that replaced the sentence
  would put a bare link into the error payload and the generated
  catalog, and an operator who has to open a runbook to find out whether
  it is the right runbook has been handed something worse than one line
  of prose.

  It governs what crosses `defexport`, never every internal tagged
  tuple, and crashes are out — exceptions are for bugs, and registering
  bug-shapes is inventorying the unknowable.

  Declared↔constructed is checked from both ends and neither is an AST
  pass hunting `kind:` keys: `use Catapult.Error` builds the component's
  error struct against this declaration, so an undeclared kind has
  nowhere to be constructed from, and `mix catapult.audit` reports the
  direction no constructor can see — a kind declared and never
  constructed, which is dead vocabulary in a catalog operators read.
  """
  @callback errors() :: [{atom(), String.t(), keyword()}]

  @doc """
  Third-party services this component wraps (v5 §2.2, §2.12):
  `{name, opts}`.

  Opts, all required: `adapter:` and `fake:` name modules and are
  checked for loadability, because a fake declared and never written is
  a hole in the no-network rule (conventions §9), and for a *shared
  behaviour*, because a fake that has drifted off its adapter's contract
  is a test lying about a system it never called; `kill_switch:` names a
  flag **this same component declares** in `feature_flags/0`, which is
  what makes §2.2's promise literal — the switch tied to the thing it
  switches instead of to a naming convention; `classification:` is a
  closed vocabulary, `t:classification/0`, highest applicable wins.

  Credentials are deliberately not a class: every adapter sends one, and
  a class every entry carries separates nothing. What the field
  classifies is application data crossing the boundary in either
  direction.
  """
  @callback externals() :: [{atom(), keyword()}]

  @doc """
  Feature flag names on the spine, collision-checked (v5 §2.10).

  A new flag is a §2.8 named decision, which is what the registry diff
  makes visible. FunWithFlags consumption waits for the delivery loop
  (conventions §13); the registration and its collision check do not.
  """
  @callback feature_flags() :: [atom()]

  @doc """
  Permission atoms on the spine, collision-checked (v5 §2.9).

  Permissions are code and roles are data: a permission is a
  component-local fact, and a role is product policy no single component
  has standing to define. `@requires_permission` enforcement waits for
  identity (Phase 7); the registry and its collision check do not.
  """
  @callback permissions() :: [atom()]

  @doc """
  Public API entries (v5 §4.4): `{{name, arity}, verb, path, opts}`.

  Opts, both required: `version:` and `audience:` (`t:audience/0`;
  versioning discipline applies to `:public`).

  §4.4's `{exported_function, path, verb, version, audience}` respelled
  rather than transcribed — the same five facts, with verb and path
  adjacent because that is how every router in the language spells a
  route, and the composition that will consume this is a mechanical
  transform of that pair.

  The function reference must name something this component exports with
  `defexport`, which is §4.4's thin-wrapper rule enforced structurally:
  any logic living only in the API layer is drift by construction.
  Collisions compare `{version, verb, path}` with every `:param` segment
  equal to every other, because `/projects/:id` and
  `/projects/:project_id` are one route to any router. Router
  composition and OpenAPI generation wait for a web layer.
  """
  @callback api_surface() :: [{{atom(), arity()}, verb(), String.t(), keyword()}]

  @doc """
  Admin surfaces mounted by the root admin router (v5 §2.2):
  `{path, module}` or `{path, module, opts}`.

  The path is a segment **beneath** the admin root, never an absolute
  `/admin/...`: where the root mounts is the composing application's
  decision (v5 §2.7), and a component spelling the prefix has hard-coded
  a fact belonging to someone else. Opts: `label:` for the nav entry.

  Catapult registers none of these — its per-component admin surfaces
  are subsumed by the dashboard (conventions §13) — which makes this the
  roster's clearest case of a registry whose first consumer is not this
  repo. The dashboard consumes them in Phase 4.
  """
  @callback admin() :: [{String.t(), module()} | {String.t(), module(), keyword()}]

  @doc """
  Audit checks this component registers (v5 §4.5's `audit` grade):
  `{check, scope, opts}`.

  `check` implements `Catapult.Audit.Check`; `scope` is a
  working-directory-relative glob, and one that is absolute or climbs
  out with `..` is a reported problem rather than a convention someone
  remembers. Opts: `policy:` — required, naming the policy node the
  check enforces; the composer checks only that it is a string, because
  resolving it means reading the doc graph, and substrate ships into
  projects whose graph belongs to the plane rather than to the package.

  The payoff is composition: a component ships its enforcement into
  every project that adopts it. This does not widen the audit's file
  scope, deliberately — each mix project composes its own check set and
  runs the audit in its own directory.

  `mix catapult.audit` is the runner. The platform's own bans
  (`Catapult.Audit.Checks.*`) are that task's floor and need no
  declaration — every project inherits them by running the audit at all;
  what a component registers here is enforcement of its *own*, which is
  what `policies/0` exists for.
  """
  @callback policies() :: [{module(), String.t(), keyword()}]

  @doc "Idempotent seeds (conventions §6); runs on every deploy."
  @callback seeds() :: :ok

  @doc "Supervision children, composed into the root (conventions §4)."
  @callback children() :: [Supervisor.child_spec() | {module(), term()} | module()]

  @doc "Readiness for the health endpoint (conventions §10)."
  @callback ready?() :: boolean()

  defmacro __using__(opts) do
    slug = Keyword.fetch!(opts, :slug)
    registry_keys = Registries.keys()

    # The empty defaults are generated from the roster: adding a
    # registry is a row, and a row that needed a hand-written default
    # here would be the table maintained twice.
    defaults =
      for key <- registry_keys do
        quote do
          @impl Catapult.Component
          def unquote(key)(), do: []
        end
      end

    overridable = Enum.map([:config, :licensing | registry_keys], &{&1, 0})

    quote do
      @behaviour Catapult.Component
      @catapult_slug unquote(slug)
      import Catapult.Component.API, only: [defexport: 2]

      # The export trace `api_surface/0` validates against, and the
      # fact the audit's every-export-has-a-test and permission checks
      # are both blocked on (v5 §2.14).
      Module.register_attribute(__MODULE__, :catapult_exports, accumulate: true)
      @before_compile Catapult.Component.API

      @impl Catapult.Component
      def slug, do: @catapult_slug

      @impl Catapult.Component
      def config, do: []

      # Empty, not defaulted: the absence is what the audit reports, and
      # a class the platform guessed would be a verdict nobody asserted.
      @impl Catapult.Component
      def licensing, do: []

      unquote(defaults)

      @impl Catapult.Component
      def seeds, do: :ok
      @impl Catapult.Component
      def children, do: []
      @impl Catapult.Component
      def ready?, do: true

      defoverridable unquote(overridable) ++ [seeds: 0, children: 0, ready?: 0]

      @doc false
      def __catapult_component__, do: true
    end
  end
end
