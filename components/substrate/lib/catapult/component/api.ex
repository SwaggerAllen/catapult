defmodule Catapult.Component.API do
  @moduledoc """
  The boundary-export macro (conventions §4, §10): `defexport` defines a
  public function wrapped in a telemetry span, so every component gets
  latency/throughput/error-rate at its public surface with zero
  per-ticket work. Permission enforcement rides the same macro when the
  identity component lands — one interception point, both concerns.

  Span events are `[:catapult, <slug>, <function>]` with start/stop/
  exception per `:telemetry.span/3`.
  """

  defmacro defexport(head, do: body) do
    {name, _meta, _args} = head

    quote do
      def unquote(head) do
        :telemetry.span([:catapult, @catapult_slug, unquote(name)], %{}, fn ->
          {unquote(body), %{}}
        end)
      end
    end
  end
end
