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
  # project (docs/non-goals.md).
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
        # there is nothing to move to and this is maintenance-watcher
        # territory (ORC-37 scoped the gate, not the advisories). cowlib
        # arrives transitively via plug_cowboy, pinned from below by
        # cowboy 2.18.0's `cowlib >= 2.19.0`; no path is reachable from
        # our own code today (the plane serves /health only).
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
  # a derivation bug put it, with nothing to say so (docs/non-goals.md).
  defp boundary do
    [
      default: [
        check: [
          apps: [
            :db_connection,
            :decimal,
            :ecto,
            :ecto_sql,
            :jason,
            :mime,
            :oban,
            :plug,
            :plug_cowboy,
            :plug_crypto,
            :postgrex,
            :req
          ]
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {Catapult.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:catapult_substrate, path: "components/substrate"},
      {:boundary, "~> 0.10", runtime: false},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.22.2"},
      {:oban, "~> 2.20"},
      {:plug_cowboy, "~> 2.8"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:ex_machina, "~> 2.7", only: :test},
      # The blessed HTTP client (conventions §1), named as a decision in
      # systems/foundation.md rather than ported in silently. `only:
      # :test` while the `:live` suite is its only consumer; the
      # constraint widens the day the first external adapter (Tracker,
      # Host, Deploy) lands in Phase 3.
      {:req, "~> 0.7", only: :test}
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
      # (docs/non-goals.md, systems/substrate.md). It does not replace
      # substrate's own gate block: the second leg needs
      # components/substrate/deps resolved and dies loudly, exit 1, if it
      # is not — an invoker that skipped a project it could not resolve
      # would be the fail-open this exists to close. A third mix project
      # is a third element here.
      "catapult.audit.all": [
        "catapult.audit",
        "cmd --cd components/substrate mix catapult.audit"
      ],
      # Infra migrations live in priv/repo/migrations_infra (the
      # foundation's file map); per-store paths compose in as stores
      # land (conventions §6).
      "ecto.setup": ["ecto.create", "ecto.migrate --migrations-path priv/repo/migrations_infra"],
      test: [
        "ecto.create --quiet",
        "ecto.migrate --quiet --migrations-path priv/repo/migrations_infra",
        "test"
      ]
    ]
  end
end
