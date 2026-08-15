defmodule Catapult.Audit.Check do
  @moduledoc """
  The contract a `policies/0` entry registers (systems/substrate.md):
  the audit is a check registry rather than a monolith, and a component
  ships its enforcement into every project that adopts it — so the ES
  family's purity floor travels with the ES family instead of being
  re-wired per project.

  `mix catapult.audit` is the runner, and the platform's own bans adopt
  this contract too (`Catapult.Audit.Checks.WallClock`, `.ProcessName`,
  `.SecretInLog`) — hosting them anywhere else would have given
  `catapult:allow` a second implementation one ticket after it got its
  first (docs/non-goals.md). `Catapult.Audit.Source` is the shared half:
  a check says what a violation *is* and says nothing about reading
  files, honouring escapes or formatting a report.

  The reversal that made hosting these here affordable is what fixes the
  report format as part of the contract: a problem naming a location
  spells it `path:line: message`, so a project that wants editor
  surfacing writes a `Credo.Check` delegating to `run/1` and no check
  logic moves.

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
