defmodule Catapult.Component.API do
  @moduledoc """
  The boundary-export macro (conventions §4, §10): `defexport` defines a
  public function wrapped in a telemetry span, so every component gets
  latency/throughput/error-rate at its public surface with zero
  per-ticket work. Permission enforcement rides the same macro when the
  identity component lands — one interception point, both concerns.

  Span events are `[:catapult, <slug>, <function>]` with start/stop/
  exception per `:telemetry.span/3`.

  ## What rides the interception point (ORC-21)

  Three things, and the rule that arrives with them matters more than any
  of them: **the metadata channel carries registered vocabulary and
  nothing else**. Never an argument, never a return body. Span and Logger
  metadata are the operational channel (conventions §10) and content
  stays out of it (v5 §2.11) — and the alternative would put
  `Catapult.Config.Secret` in the position of defending a second surface.

    * **`component:` in Logger metadata at every export entry**, so ad
      hoc logging inside a component still arrives structured. That fence
      is what makes ad hoc logging legitimate at all: logs are write-only
      and unregistered, nothing parses or alerts on them, so the only
      thing they owe is being attributable.
    * **`trace_id:` when, and only when, there is none.** An export that
      overwrote an inherited trace id would cut every trace at the first
      internal boundary crossing, which is the seam tracing exists to
      cross; generating one where there is none is what makes an export
      the root of its own trace.
    * **A registered error kind on the span's stop metadata**, taken from
      the export's own return — v5 §2.2's error-rate-by-kind, and the
      first thing to put anything in metadata that was empty before.

  The outer `component:` is restored on the way out, because a nested
  export that left its own slug behind would misattribute every later log
  line in its caller — a bug that costs two `Logger.metadata/1` calls to
  not have.

  ## The export trace

  The macro also leaves a trace: each `defexport` accumulates its
  `{name, arity}`, and `__catapult_component__/0`'s sibling
  `__catapult_exports__/0` is generated from it. Without that, nothing
  in the substrate could answer "is this function a boundary export" —
  which is the whole of v5 §4.4's thin-wrapper enforcement, and what
  `api_surface/0` validates against. The payoff outruns that registry:
  the audit's every-export-has-a-test check and its exported-mutating-
  function permission check (v5 §2.14) are both blocked on this same
  fact, and neither now has to invent it.
  """

  require Logger

  defmacro defexport(head, do: body) do
    {name, _meta, args} = head
    arity = length(List.wrap(args))

    quote do
      @catapult_exports {unquote(name), unquote(arity)}

      # `unquote(__MODULE__)` rather than the literal alias: generated
      # code cannot rely on an alias in the adopting module's scope, and
      # injecting one there would be this macro leaving a name behind.
      def unquote(head) do
        unquote(__MODULE__).entering(@catapult_slug, fn ->
          :telemetry.span([:catapult, @catapult_slug, unquote(name)], %{}, fn ->
            result = unquote(body)
            {result, unquote(__MODULE__).span_metadata(result)}
          end)
        end)
      end
    end
  end

  @doc """
  Runs `fun` with the export's Logger metadata floor in place.

  A function rather than more quoted code: the rule is one
  implementation, and a macro that inlined it would put four lines into
  every export in every generated project.
  """
  @spec entering(atom(), (-> result)) :: result when result: term()
  def entering(slug, fun) do
    outer = Logger.metadata()
    Logger.metadata(floor(slug, outer))

    try do
      fun.()
    after
      # `nil` deletes the key, so an export called from outside any other
      # restores absence rather than leaving its own slug behind.
      Logger.metadata(component: Keyword.get(outer, :component))
    end
  end

  @doc """
  The span's stop metadata for an export's return value.

  Registered vocabulary only: a declared error kind is a closed set the
  composer validated and an operator can group by, which is what makes
  error-rate-by-kind a metric rather than a cardinality incident.
  Everything else returns nothing at all — including, deliberately, the
  reason inside an `{:error, term}` that is not a registered kind.
  """
  @spec span_metadata(term()) :: map()
  def span_metadata({:error, %{kind: kind}}) when is_atom(kind) and not is_nil(kind) do
    %{error_kind: kind}
  end

  def span_metadata(_result), do: %{}

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      @doc false
      # Accumulated attributes read back newest-first; declaration order
      # is what a report should show.
      def __catapult_exports__, do: Enum.reverse(@catapult_exports)
    end
  end

  defp floor(slug, outer) do
    if Keyword.has_key?(outer, :trace_id) do
      [component: slug]
    else
      [component: slug, trace_id: trace_id()]
    end
  end

  # Random rather than derived: a trace id has to be unique across nodes
  # that share nothing, and the only thing every node shares is entropy.
  defp trace_id, do: 8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
end
