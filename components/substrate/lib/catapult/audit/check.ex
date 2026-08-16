defmodule Catapult.Audit.Check do
  @moduledoc """
  The contract a `policies/0` entry registers (systems/substrate.md):
  the audit is a check registry rather than a monolith, and a component
  ships its enforcement into every project that adopts it — so the ES
  family's purity floor travels with the ES family instead of being
  re-wired per project.

  The behaviour lands here; the loop that calls it, and the checks that
  adopt it, are ORC-21's. A registry whose entries reference modules has
  to say what the module is, or its collision check is checking the
  names of things with no contract.

  One callback, and it takes the scope the entry registered it under —
  a working-directory-relative glob, which is what keeps a registered
  check from reaching across mix projects. Each project composes its own
  check set and runs the audit in its own directory.

  Returning problems rather than raising is the audit's all-problems-at-
  once style (`Catapult.Component.Composer`): one round trip per problem
  is hostile, and a check that raised would take the rest of the report
  down with it.
  """

  @doc """
  Every problem this check finds under `scope`, as report lines.

  An empty list is a pass. The scope is the glob the registering
  component declared, relative to the working directory.
  """
  @callback run(scope :: String.t()) :: [String.t()]
end
