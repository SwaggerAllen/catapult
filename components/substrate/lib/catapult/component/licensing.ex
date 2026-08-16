defmodule Catapult.Component.Licensing do
  @moduledoc """
  `licensing/0`'s home: the distribution vocabulary, the declaration's
  shape, and reading one component's answer (systems/substrate.md).

  The registry outside the roster table that claims no name, so
  `Catapult.Component.Registries` cannot hold it — its `:claim` and
  `:identity` columns are the reason that table exists, and two
  components declaring `Apache-2.0` is the ordinary case rather than a
  collision. The shape hazard behind the same fact, named so the next
  pass does not walk into it: a keyword list *is* a list of two-tuples,
  so a table-driven aggregator reads one declaration as two entries.

  ## Shape here, policy in the audit

  This module says what a well-formed declaration looks like and nothing
  about whether the license is acceptable. `Catapult.Component.Composer`
  folds these problems into its report, which runs at boot as well as
  under the audit — and an allowlist that ran at boot would be a
  production node refusing to start because a transitive dependency's
  license string is unrecognized. The severity that fits a legal fact is
  CI red (`LICENSING.md`, docs/non-goals.md).

  The policy — which classes are checked, against which identifiers, and
  for which reason — is `Catapult.Audit.License`'s, which reads
  `declared/1` and holds no part of this.

  ## An undeclared component is not a shape problem

  `licensing/0`'s empty default is legal here and reported there. It has
  to be legal, or `use Catapult.Component` would stop being sufficient
  to compile; it has to be reported, or a component whose author will
  not say who receives it becomes a silent pass.
  """

  @distributions [:distributed, :service, :internal]
  @known_opts [:distribution, :license]

  @typedoc "A well-formed declaration, or why it is not one."
  @type declared ::
          {:ok, Catapult.Component.distribution(), String.t()} | :none | :malformed

  @doc "The declared distribution classes, in `LICENSING.md`'s order."
  @spec distributions() :: [atom()]
  def distributions, do: @distributions

  @doc "The opts `licensing/0` knows."
  @spec known_opts() :: [atom()]
  def known_opts, do: @known_opts

  @doc """
  One component's declaration.

  `:none` is the empty default — an absence, which the audit reports and
  the composer does not. `:malformed` is anything `problems/1` has
  already spoken about, so a consumer contributes no subject rather than
  reporting the same defect twice.
  """
  @spec declared(module()) :: declared()
  def declared(component) do
    case component.licensing() do
      [] ->
        :none

      opts when is_list(opts) ->
        with true <- Keyword.keyword?(opts),
             {:ok, distribution} when distribution in @distributions <-
               Keyword.fetch(opts, :distribution),
             {:ok, license} when is_binary(license) <- Keyword.fetch(opts, :license) do
          {:ok, distribution, license}
        else
          _ -> :malformed
        end

      _ ->
        :malformed
    end
  end

  @doc """
  Everything wrong with one component's `licensing/0`, all at once.

  The composer's half of the report (see the moduledoc): unknown opt,
  missing opt, a `distribution:` outside the vocabulary — everything
  checkable with no environment at all.
  """
  @spec problems(module()) :: [String.t()]
  def problems(component) do
    where = "#{inspect(component)}'s licensing/0"

    case component.licensing() do
      [] -> []
      opts when is_list(opts) -> opt_problems(opts, where)
      other -> ["#{where} returned #{inspect(other)}, expected a keyword list"]
    end
  end

  defp opt_problems(opts, where) do
    if Keyword.keyword?(opts) do
      unknown(opts, where) ++ missing(opts, where) ++ typed(opts, where)
    else
      ["#{where} returned #{inspect(opts)}, expected a keyword list"]
    end
  end

  defp unknown(opts, where) do
    for {opt, _value} <- opts, opt not in @known_opts do
      "#{where} carries unknown opt #{inspect(opt)} (known: #{inspect(@known_opts)})"
    end
  end

  # Both opts are required, so a half-declaration is two facts short of
  # meaning anything: a license says nothing about obligation without a
  # class, and a class says nothing about terms.
  defp missing(opts, where) do
    for opt <- @known_opts, not Keyword.has_key?(opts, opt) do
      "#{where} is missing required opt #{inspect(opt)}"
    end
  end

  # Unknown opts are `unknown/2`'s line; this types only the two the
  # declaration knows, so a typo is one problem rather than two.
  defp typed(opts, where) do
    distribution_problem(opts, where) ++ license_problem(opts, where)
  end

  defp distribution_problem(opts, where) do
    case Keyword.fetch(opts, :distribution) do
      {:ok, value} when value in @distributions ->
        []

      {:ok, value} ->
        [
          "#{where} has a distribution #{inspect(value)} that is not one of " <>
            "#{inspect(@distributions)}"
        ]

      :error ->
        []
    end
  end

  defp license_problem(opts, where) do
    case Keyword.fetch(opts, :license) do
      {:ok, value} when is_binary(value) -> []
      {:ok, value} -> ["#{where} has a license #{inspect(value)} that is not a string"]
      :error -> []
    end
  end
end
