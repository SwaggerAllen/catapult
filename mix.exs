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
      deps: deps(),
      compilers: [:boundary] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      hex: hex()
    ]
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
        # cowlib 2.19.0, both unpatched upstream as of 2026-08-15 — no
        # release to move to, so this is maintenance-watcher territory
        # (ORC-37 scoped the gate, not the advisories). cowlib arrives
        # transitively via plug_cowboy; neither path is reachable from
        # our own code today (the plane serves /health only).
        # HTTP response splitting, cow_http_struct_hd:escape_string/2.
        "EEF-CVE-2026-43966",
        # Cookie request header injection, cow_cookie:cookie/1.
        "EEF-CVE-2026-43969"
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
      {:ex_machina, "~> 2.7", only: :test}
    ]
  end

  defp aliases do
    [
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
