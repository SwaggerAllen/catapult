defmodule Catapult.Foundation.Policies.ErlangHttp do
  @moduledoc """
  The Erlang half of conventions §11, at AST grade (ORC-52,
  systems/foundation.md): no plane module calls a pure Erlang HTTP
  client directly, by remote call or by `apply/3` on a literal module
  atom.

  This is not "no plane module calls a model provider through Erlang" —
  that would need to follow a URL back to its binding, which is data
  decided at runtime and normally read from configuration, and this
  repo has already refused that inference twice
  (`systems/substrate.md`, "What a check may infer").
  What is decidable at this grade is the transport: `:httpc.request/4`
  and `apply(:httpc, :request, _)` name their module in the literal
  source, the same way `DateTime.utc_now` does for
  `Catapult.Audit.Checks.WallClock`. The ban is deliberately broader
  than a model-call check — it catches every unbounded Erlang egress
  from plane code, not only the model-shaped one — because the narrower
  check is the one that cannot be built honestly.

  `:inets` is banned alongside `:httpc` because it is the application
  `:httpc` needs `start/0` to run under; `:hackney`, `:gun` and
  `:ibrowse` are the other Erlang HTTP clients on hex.pm. A computed
  module is out of reach of this check and is not chased, for the same
  reason a computed URL is not.

  Escape: `# catapult:allow erlang_http`, on the offending line or the
  comment line directly above it (`Catapult.Audit.Source`).
  """

  @behaviour Catapult.Audit.Check

  alias Catapult.Audit.Source

  @tag "erlang_http"
  @modules [:httpc, :inets, :hackney, :gun, :ibrowse]

  @doc "The bare name a `catapult:allow` comment gives this check."
  @spec tag() :: String.t()
  def tag, do: @tag

  @impl Catapult.Audit.Check
  def run(scope), do: Source.scan(scope, @tag, &violations/1)

  defp violations(source) do
    Source.collect(source.ast, fn
      {{:., _dot, [module, function]}, _meta, args} = node
      when is_atom(module) and is_atom(function) and is_list(args) ->
        found(module, node)

      {:apply, _meta, [module, function, _args]} = node
      when is_atom(module) and is_atom(function) ->
        found(module, node)

      _node ->
        []
    end)
  end

  defp found(module, node) do
    if module in @modules do
      [
        {Source.line(node),
         "call into #{inspect(module)}, a pure Erlang HTTP client (no plane module reaches " <>
           "one directly; conventions §11, systems/foundation.md)"}
      ]
    else
      []
    end
  end
end
