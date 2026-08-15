defmodule Catapult.Component.API do
  @moduledoc """
  The boundary-export macro (conventions §4, §10): `defexport` defines a
  public function wrapped in a telemetry span, so every component gets
  latency/throughput/error-rate at its public surface with zero
  per-ticket work. Permission enforcement rides the same macro when the
  identity component lands — one interception point, both concerns.

  Span events are `[:catapult, <slug>, <function>]` with start/stop/
  exception per `:telemetry.span/3`.

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

  defmacro defexport(head, do: body) do
    {name, _meta, args} = head
    arity = length(List.wrap(args))

    quote do
      @catapult_exports {unquote(name), unquote(arity)}

      def unquote(head) do
        :telemetry.span([:catapult, @catapult_slug, unquote(name)], %{}, fn ->
          {unquote(body), %{}}
        end)
      end
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      @doc false
      # Accumulated attributes read back newest-first; declaration order
      # is what a report should show.
      def __catapult_exports__, do: Enum.reverse(@catapult_exports)
    end
  end
end
