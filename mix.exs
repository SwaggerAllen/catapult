defmodule Catapult.MixProject do
  use Mix.Project

  # Catapult: the platform (docs/v5-design-decisions.md), built per
  # docs/build-plan.md. Single OTP app + Boundary (conventions §4);
  # shippable shared components live under components/ as path deps.
  def project do
    [
      app: :catapult,
      version: "0.1.0",
      # Floor, not pin — the pin is .tool-versions; CI enforces it.
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      boundary: boundary(),
      deps: deps(),
      compilers: [:boundary] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      hex: hex(),
      licensing: licensing()
    ]
  end

  # Arms `mix catapult.audit`'s license check (ORC-51, systems/foundation.md)
  # rather than leaving the plane inert: every component here declares
  # `licensing/0` as `[distribution: :service, license: "AGPL-3.0-only"]`,
  # and `{:service, :listed}` arms nothing — the plane's own dependency
  # closure stays unchecked exactly as LICENSING.md's table says it should.
  # No `package:` block: the plane is published nowhere, so a `licenses:`
  # entry there would assert conveyance that is false and arm the whole
  # closure on that false premise (docs/non-goals.md).
  #
  # The list is Catapult's five plus the plane's own identifier — it has
  # to include `AGPL-3.0-only` or the plane's own subject reads as
  # unplaceable — and every plane component declares the same class,
  # because a subject needing a different one belongs in its own mix
  # project (systems/substrate.md).
  defp licensing do
    [allow: ~w(AGPL-3.0-only Apache-2.0 MIT BSD-2-Clause BSD-3-Clause ISC)]
  end

  # `mix hex.audit` is the load-bearing supply gate (conventions §2,
  # systems/substrate.md). Advisories we cannot act on are named here
  # per ID rather than absorbed by a silent gate: the exit code matches
  # a clean run, the epistemic status does not. Never ignore a *package*
  # — that re-blinds the gate to the next advisory against it, which is
  # the failure this list exists to prevent. Hex warns that an entry
  # matching nothing can be removed, so each one expires by itself the
  # day the dependency is bumped.
  defp hex do
    [
      ignore_advisories: [
        # cowlib 2.19.0, all three unpatched upstream as of 2026-08-18
        # — 2.19.0 is the newest release and every advisory names it, so
        # there is nothing to move to, and that is the whole of why
        # these stay ignored (ORC-37 scoped the gate, not the
        # advisories). cowlib arrives transitively via plug_cowboy,
        # pinned from below by cowboy 2.18.0's `cowlib >= 2.19.0`. This
        # ignore used to also lean on the plane's single listener
        # serving `/health` only; ORC-9's `DispatchPlug` gave that same
        # listener a second inbound path (`/dispatch/*`, forwarding to
        # delivery's boundary export), so that ground is gone — the
        # plane now has more than one path into the cowboy/cowlib stack
        # these advisories are about. Nothing here rests on request
        # paths anymore; the version-drift argument above is load-
        # bearing on its own.
        # HTTP response splitting, cow_http_struct_hd:escape_string/2.
        "EEF-CVE-2026-43966",
        # Cookie request header injection, cow_cookie:cookie/1.
        "EEF-CVE-2026-43969",
        # Link header directive smuggling, cow_link:link/1: `>` in the
        # target closes the URI slot early, letting a caller-supplied
        # value append further entries with chosen `rel` directives.
        # Published after ORC-48's first green run, which is how a
        # registry-sourced gate fails a branch that changed no
        # dependency — the signal is the registry moving, not the diff.
        # Nothing in the tree calls cow_link.
        "EEF-CVE-2026-43971"
      ]
    ]
  end

  # Boundary's external-dependency checking, armed now against one
  # boundary rather than later against all of them (ORC-21,
  # systems/foundation.md). v5 §2.14 promotes the adapter conventions to
  # compile grade — only Store subcomponents on Ecto, only the outbox
  # wrapper on Oban's insert surface, only adapters on Req, no model-call
  # library in plane code — and every one of those is a rule *about a
  # sub-boundary*, while the tree has exactly one boundary today. What
  # can be armed is the checking, so a carve-out lands already checked
  # instead of retrofitted N boundaries at a time.
  #
  # It is `check: [apps: ...]` rather than `type: :strict` for a
  # mechanical reason worth writing down, since strict is what the
  # sketch drew. Strict would additionally require naming implicit
  # boundaries inside `:catapult_substrate`, and Boundary's cached view
  # drops a *path dep*'s boundaries on every incremental compile and
  # rebuilds them only from loaded applications — which the cache-hit
  # path does not load. The result is a clean `mix compile --force` and
  # a `mix compile` that reports every substrate call as forbidden, so
  # the second gate run in any CI job fails on state rather than on code
  # (measured, not inferred). A generated project fetches substrate from
  # hex, so the defect has no purchase there and its mix.exs states
  # `type: :strict` (systems/platform_content.md).
  #
  # The list is no longer the four rules' applications, and ORC-21's
  # accepted cost — "a newly added dependency is unchecked until it is
  # named here, which is a line in the same diff that added it" — is
  # retired with it (ORC-50). That price assumes the omission gets
  # noticed and nothing noticed it: an application absent from this list
  # is not partially checked, it is silently exempt, and the list was
  # short of six the day it was written. So it is now the whole of what
  # a `:prod` build can reach and Boundary can restrain, and
  # `Catapult.Audit.BoundaryApps` re-derives that set from the tree on
  # every `mix catapult.audit` rather than trusting a diff to remember.
  # Three exclusions are derived there, never written here: `:boundary`
  # itself, applications contributing no Elixir modules (cowboy, cowlib,
  # ranch, telemetry — a call into one resolves to no application, so no
  # entry could restrain it), and path deps, because naming
  # `:catapult_substrate` reproduces the defect above through the list
  # instead of through strict (measured at twelve forbidden references
  # and a red build). The check demands coverage, never equality, which
  # is what keeps `:req` — `only: :test`, and named deliberately —
  # legal. It stays a literal a reviewer reads rather than a derivation
  # inside this function: a computed list would fail open exactly where
  # a derivation bug put it, with nothing to say so
  # (systems/foundation.md).
  defp boundary do
    [
      default: [
        check: [
          apps: [
            :commanded,
            :commanded_eventstore_adapter,
            :date_time_parser,
            :db_connection,
            :decimal,
            :ecto,
            :ecto_sql,
            :eventstore,
            :finch,
            :fsm,
            :gen_stage,
            :hpax,
            :jason,
            :joken,
            :joken_jwks,
            :jose,
            :libgraph,
            :mime,
            :mint,
            :nimble_options,
            :nimble_pool,
            :makeup,
            :makeup_eex,
            :makeup_elixir,
            :makeup_html,
            :mdex,
            :mdex_native,
            :nimble_parsec,
            :oban,
            :phoenix,
            :phoenix_html,
            :phoenix_live_view,
            :phoenix_pubsub,
            :phoenix_storybook,
            :phoenix_template,
            :plug,
            :plug_cowboy,
            :plug_crypto,
            :postgrex,
            :req,
            :solid,
            :rustler_precompiled,
            :telemetry_registry,
            :tesla,
            :websock,
            :websock_adapter,
            :yaml_elixir
          ]
        ]
      ]
    ]
  end

  def application do
    [
      # `:xmerl` (OTP-shipped) backs `Catapult.Dsl.Grammar`'s root_tag +
      # XSD validation (dsl-syntax.md §10) — no Hex dependency needed,
      # and, like `:httpc`, a pure Erlang application Boundary cannot
      # restrain (`systems/foundation.md`), so it carries no `boundary:
      # default: check: apps:` entry.
      extra_applications: [:logger, :runtime_tools, :xmerl],
      mod: {Catapult.Application, []}
    ]
  end

  # `storybook/` compiles in every environment, deliberately. It is
  # design-owned (`pipeline.config.json`'s `designOwnedPaths`), which
  # makes it the one tree where authored Elixir arrives without a dev
  # pass behind it — so leaving it off this list is what would make it
  # unchecked, not what would keep it out of the way. On the path, the
  # whole gate set (format, credo, compile --warnings-as-errors, the
  # boundary compiler) covers it like any other source.
  defp elixirc_paths(:test), do: ["lib", "storybook", "test/support"]
  defp elixirc_paths(_), do: ["lib", "storybook"]

  defp deps do
    [
      {:catapult_substrate, path: "components/substrate"},
      {:boundary, "~> 0.10", runtime: false},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.22.2"},
      {:oban, "~> 2.20"},
      {:plug_cowboy, "~> 2.8"},
      {:jason, "~> 1.4"},
      # Type-level acyclicity over the edge-instance graph, the extends:
      # chain, and the workflow gate/environment ordering (dsl-syntax.md
      # §4, §11, §13) — conventions §1's blessed graph library, ORC-5.
      {:libgraph, "~> 0.16"},
      # The bundle loader's YAML reader (ORC-5, systems/core_dsl.md):
      # already resolved transitively via mix_audit's own dependency, so
      # this promotes an existing lock entry to a direct runtime dep
      # rather than introducing a new supply-chain leaf.
      {:yaml_elixir, "~> 2.12"},
      # Event-sourcing machinery (conventions §1's blessed list; v5
      # §2.4 — "Commanded is the blessed event-sourcing machinery for
      # target apps... the control plane already runs it" from ORC-6
      # on): the aggregate/router/application layer, its Postgres event
      # store adapter, and the store itself (systems/engine.md). The
      # env-switched adapter (`Commanded.EventStore.Adapters.InMemory`
      # for dev/test, this pair for prod) ships inside `commanded`
      # itself, so no third dependency is needed for that half.
      {:commanded, "~> 1.4"},
      {:commanded_eventstore_adapter, "~> 1.4"},
      {:eventstore, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      # Armed by `mix catapult.audit`'s own sleeper check the moment
      # `:phoenix` entered the dependency tree (v5 §2.14): a Phoenix
      # surface without Sobelow is a static-analysis gap the audit
      # refuses to leave silent. `only: [:dev, :test], runtime: false`
      # like every other analysis-only tool here, which is also why it
      # needs no `boundary: check: apps:` entry.
      {:sobelow, "~> 0.15", only: [:dev, :test], runtime: false},
      {:ex_machina, "~> 2.7", only: :test},
      # The blessed HTTP client (conventions §1). Was `only: :test`
      # (the `:live` suite's own dependency) until the first external
      # adapter landed — ORC-9's Actions adapter, which is that adapter
      # (`systems/foundation.md`'s own note that the constraint widens
      # "the day the first external adapter (Tracker, Host, Deploy)
      # lands"). Now an ordinary runtime dep.
      {:req, "~> 0.7"},
      # Liquid templates (conventions §1's blessed choice for prompt
      # rendering; `dsl-syntax.md` §9, `systems/generation.md`) — named
      # in ORC-9's own scope text ("Liquid/Solid, ordered walks").
      {:solid, "~> 1.3"},
      # JWT + JWKS verification for GitHub Actions OIDC (v5 §7.12.1: "JWT
      # + JWKS verification is stock Elixir machinery (joken/joken_jwks-
      # grade), not custom crypto") — named in ORC-9's own scope text.
      {:joken, "~> 2.6"},
      {:joken_jwks, "~> 1.7"},
      # The screen machinery `docs/ui-spec.md` and `systems/dashboard.md`
      # describe: `Phoenix.Component` for the presentational shells design
      # authors under `storybook/screens/**` (design-owned per
      # `pipeline.config.json`), and PhoenixStorybook for the stories that
      # exercise them. Ordinary runtime deps rather than `only: [:dev,
      # :test]`: the storybook ships in a release deliberately — main is
      # both prod and staging today, and the storybook is wanted on the
      # staging release once the two separate.
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_storybook, "~> 1.3"}
    ]
  end

  defp aliases do
    [
      # The gate name stays, its content grows: `mix deps.audit` is
      # already a quality gate and a ci.yml step, so folding the
      # Hex-sourced signal in here arms it without touching a file only
      # the author can push. Order is load-bearing — `hex.audit` reads
      # the registry and must run before anything compiles the tree,
      # and running it first also means the Hex signal reports even
      # when a later step would fail. Shadowing a task and re-invoking
      # it as the alias's own last element is the same shape as `test`
      # below. Both audits run; only the Hex one is load-bearing
      # (conventions §2).
      "deps.audit": ["hex.audit", "deps.audit"],
      # The audit's globs are rooted at the working directory, so
      # `mix catapult.audit` here reads as though it audits the
      # repository and audits only the root project — the one gate whose
      # absence is invisible (ORC-30). The invoker that knows this repo
      # has two mix projects lives here, in AGPL plane code that never
      # reaches a hex consumer and whose job is precisely to know the
      # layout; the shipped task stays layout-ignorant
      # (systems/substrate.md). It does not replace substrate's own gate
      # block: the second leg needs components/substrate/deps resolved
      # and dies loudly, exit 1, if it is not — an invoker that skipped
      # a project it could not resolve would be the fail-open this
      # exists to close. A third mix project is a third element here.
      "catapult.audit.all": [
        "catapult.audit",
        "cmd --cd components/substrate mix catapult.audit"
      ],
      # Infra migrations live in priv/repo/migrations_infra (the
      # foundation's file map); per-store paths compose in as stores
      # land (conventions §6) — the engine's own tables are the first
      # of those, at the default `priv/repo/migrations` Ecto already
      # looks in without a `--migrations-path` override.
      #
      # The second `ecto.migrate` is a `cmd`, a genuinely separate `mix`
      # process, not a second in-VM `Mix.Task.run` call: Mix only runs a
      # given task once per invocation and silently no-ops a repeat
      # call to the *same task name* even with different arguments
      # (measured — the plain second form left `priv/repo/migrations`
      # unmigrated and every engine test failed on a missing table).
      "ecto.setup": [
        "ecto.create",
        "ecto.migrate --migrations-path priv/repo/migrations_infra",
        "cmd mix ecto.migrate"
      ],
      test: [
        "ecto.create --quiet",
        "ecto.migrate --quiet --migrations-path priv/repo/migrations_infra",
        "cmd mix ecto.migrate --quiet",
        "test"
      ]
    ]
  end
end
