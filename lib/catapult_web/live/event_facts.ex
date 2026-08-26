defmodule CatapultWeb.Live.EventFacts do
  @moduledoc """
  Display facts read off the raw event log rather than a stored
  projection column — the "read the log for a display fact" pattern
  `Catapult.Engine.Projections.GateComments`/`CommentFeedback` already
  establish for "who resolved it," reused here for the one other fact
  this system's screens want that has no projection column of its own.

  `board` and `ticket` both render a blocked card's flavor label (v5
  §7.6 — `needs-review` / `needs-setup` / bare failure), but
  `Catapult.Delivery.Store.FeatureLifecycle` carries no flavor column:
  `Catapult.Delivery.FeatureLifecycle.Projection.block/2` records only
  the origin position. `RunFailed.reason` is the nearest fact the log
  actually carries — a short machine tag, not the closed three-value
  set v5 §7.6 sketches — so this reads the most recent one rather than
  inventing a value neither the event nor the projection has.
  """

  alias Catapult.Engine.Application
  alias Catapult.Engine.Events.RunFailed

  @doc "The most recent `RunFailed.reason` in `project_id`'s stream, or `\"failure\"` if none — the honest default for a block this system cannot otherwise explain."
  @spec blocked_flavor(binary()) :: String.t()
  def blocked_flavor(project_id) do
    case Commanded.EventStore.stream_forward(Application, "project-" <> project_id) do
      {:error, :stream_not_found} ->
        "failure"

      stream ->
        stream
        |> Enum.reduce(nil, fn
          %{data: %RunFailed{reason: reason}}, _acc -> reason
          _event, acc -> acc
        end)
        |> Kernel.||("failure")
    end
  end
end
