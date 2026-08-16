defmodule Catapult.Audit.Checks.WallClock do
  @moduledoc """
  The injected-clock ban at AST grade (conventions §9): a direct
  `DateTime.utc_now` or `NaiveDateTime.utc_now` in the audited scope,
  where domain code should be taking `Catapult.Clock` as a dependency.

  This moduledoc spells the call it forbids, which the grep this replaces
  could not afford to do — the difference the AST grade buys, stated at
  the first place it shows. A call is a call and a string is a string;
  prose, a docstring and a test asserting the ban works are all invisible
  to it.

  Escape: `# catapult:allow utc_now`, on the offending line or the comment
  line directly above it (`Catapult.Audit.Source`). `Catapult.Clock.System`
  is the one sanctioned use in this package.
  """

  @behaviour Catapult.Audit.Check

  alias Catapult.Audit.Source

  @tag "utc_now"
  @modules [:DateTime, :NaiveDateTime]

  @doc "The bare name a `catapult:allow` comment gives this check."
  @spec tag() :: String.t()
  def tag, do: @tag

  @impl Catapult.Audit.Check
  def run(scope), do: Source.scan(scope, @tag, &violations/1)

  defp violations(source) do
    Source.collect(source.ast, fn
      {{:., _dot, [module, :utc_now]}, _meta, args} = node when is_list(args) ->
        found(module, node)

      _node ->
        []
    end)
  end

  defp found(module, node) do
    case Enum.find(@modules, &Source.alias?(module, &1)) do
      nil ->
        []

      name ->
        [{Source.line(node), "bare #{name}.utc_now (inject Catapult.Clock; conventions §9)"}]
    end
  end
end
