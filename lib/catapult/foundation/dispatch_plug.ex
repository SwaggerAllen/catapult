defmodule Catapult.Foundation.DispatchPlug do
  @moduledoc """
  Registry-driven dispatch over `api_surface/0` (ORC-9's original
  hand-matching, replaced by ORC-35's design pass — see
  `systems/foundation.md`'s "Landed as a shape" note). Reads the same
  aggregated `api_surface/0` table `Catapult.Component.Composer`
  already builds and matches `{verb, path}` against it at request
  time, the same shape route-identity collision-checking already uses
  for `:param` segments — no macro or behaviour coupling, so the
  compile-connected cap (`--fail-above 0`) stays untouched. A match
  dispatches with `apply(module, function, [conn | params])`, a
  runtime call through an atom pulled from a list, the same shape
  `Catapult.Component.Composer` already uses to call every registry
  callback on a module it never `alias`es or `require`s.

  `/health` is one more entry through the same matching function
  rather than a hardcoded first clause, keeping `Catapult.HealthEndpoint`'s
  own 404-everything-else behavior on its own path.

  Mounted first in `CatapultWeb.Endpoint`'s pipeline
  (`systems/dashboard.md`): unlike ORC-9's version, an unmatched path
  is passed through unhalted rather than answered with a 404 here —
  `CatapultWeb.Router` sits right behind it and owns the terminal
  404 for anything neither mechanism claims. This plug's own job
  narrowed the day a router existed to hand off to, which is what
  "when dashboard's router lands... this listener's hand-wiring is
  what gets deleted" (this doc's own design pass) meant in practice.
  """
  @behaviour Plug

  alias Catapult.Boot
  alias Catapult.Component.Composer
  alias Catapult.HealthEndpoint

  @impl Plug
  def init(opts), do: HealthEndpoint.init(opts)

  @impl Plug
  def call(conn, health_opts) do
    case route(conn) do
      :health -> HealthEndpoint.call(conn, health_opts)
      {module, function, params} -> apply(module, function, [conn | params])
      nil -> conn
    end
  end

  defp route(%Plug.Conn{path_info: ["health" | _]}), do: :health

  defp route(conn) do
    Enum.find_value(api_routes(), &match_route(&1, conn))
  end

  defp api_routes do
    Boot.components() |> Composer.inventory() |> Map.fetch!(:api_surface)
  end

  defp match_route(entry, %Plug.Conn{method: method, path_info: path_info}) do
    with verb when not is_nil(verb) <- verb(method),
         true <- entry.verb == verb,
         {:ok, params} <- capture(path_segments(entry.path), path_info) do
      {name, _arity} = entry.function
      {entry.component, name, params}
    else
      _ -> nil
    end
  end

  defp path_segments(path), do: path |> String.split("/") |> Enum.reject(&(&1 == ""))

  # Every declared `:param` segment captures positionally, in the
  # order it appears in the path — the same order `apply/3`'s
  # `[conn | params]` hands to the target export.
  defp capture([], []), do: {:ok, []}

  defp capture([":" <> _ | declared], [segment | actual]) do
    with {:ok, rest} <- capture(declared, actual), do: {:ok, [segment | rest]}
  end

  defp capture([segment | declared], [segment | actual]), do: capture(declared, actual)
  defp capture(_declared, _actual), do: :error

  defp verb("GET"), do: :get
  defp verb("POST"), do: :post
  defp verb("PUT"), do: :put
  defp verb("PATCH"), do: :patch
  defp verb("DELETE"), do: :delete
  defp verb(_other), do: nil
end
