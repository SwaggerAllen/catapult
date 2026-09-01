defmodule Catapult.Substrate.MixProject do
  use Mix.Project

  # The elixir-target platform substrate (systems/substrate.md): the
  # component behaviour + registries, the boundary-export macro, the
  # audit, health, clock, and seeds. Shipped to every target app;
  # Catapult itself is the first consumer (path dep from the repo root).
  def project do
    [
      app: :catapult_substrate,
      version: "0.1.0",
      # Floor, not pin: the pin lives in .tool-versions and CI enforces
      # it; the floor is what lets older local toolchains compile.
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      licensing: licensing()
    ]
  end

  # `licenses:` is what arms `mix catapult.audit`'s license check
  # (ORC-16, LICENSING.md): a project with a package block is fetched by
  # somebody, and being fetched is what conveyance is. It is also the one
  # declaration nothing that ships can forget — `mix hex.build` refuses a
  # package without it — which is why the check is armed by this rather
  # than by a task that knows where this repository keeps its components.
  # The rest of the package metadata (description, links) lands with the
  # release train, not here.
  defp package do
    [licenses: ["Apache-2.0"]]
  end

  # The standard the check holds this tree to, stated here rather than
  # compiled into `Catapult.Audit.License`: that module ships into every
  # generated project, and five identifiers inside it would be Catapult's
  # legal position imposed on codebases nobody here has read
  # (systems/substrate.md). A generated project gets these five written
  # literally into its own mix.exs by `bundles/default`
  # (systems/platform_content.md); substrate is not a generated project,
  # so it states them by hand.
  #
  # The criterion is not "permissive" but *imposes no terms on the
  # linking application*, which is what LICENSING.md actually requires
  # and what makes an addition decidable rather than a debate about what
  # permissive means. ISC is not decorative: cowboy, cowlib and ranch are
  # all ISC, so the first shipped component that serves HTTP lands on it.
  #
  # `overrides:` would live here too, naming a license a human read out
  # of a package's own LICENSE. There are none: every dependency in the
  # checked closure declares a clean SPDX identifier today.
  defp licensing do
    [allow: ~w(Apache-2.0 MIT BSD-2-Clause BSD-3-Clause ISC)]
  end

  # `:crypto` for the export macro's trace ids (Catapult.Component.API);
  # it is OTP's, not a dependency, but a release that did not list it
  # would leave every export raising on its first log line.
  def application, do: [extra_applications: [:crypto, :logger]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:plug, "~> 1.18"},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
