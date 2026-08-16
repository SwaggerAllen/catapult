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
      elixirc_paths: elixirc_paths(Mix.env())
    ]
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
