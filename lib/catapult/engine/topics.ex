defmodule Catapult.Engine.Topics do
  @moduledoc """
  `engine:*` PubSub topics as functions, never raw strings (conventions
  §3, v5 §2.2's `pubsub_topics/0`). Rides `Commanded.PubSub` — already
  configured `pubsub: :local` on `Catapult.Engine.Application`
  (`config.exs`, a build-shape constant at `topology: single`) and
  already started as part of that application's own supervision tree
  — rather than a second, redundant `Registry`: the scheduler's "write
  the `ready_scopes` row" is a broadcast, never a materialized table
  (`systems/engine.md`), and this is the broadcast mechanism the rest
  of that standing decision already assumed exists.
  """

  alias Catapult.Engine.Application

  @doc "The topic one project's ready-scope announcements broadcast on."
  @spec ready_scopes(binary()) :: String.t()
  def ready_scopes(project_id), do: "engine:ready_scopes:#{project_id}"

  @doc "Subscribes the caller to `topic`."
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(topic), do: Commanded.PubSub.subscribe(Application, topic)

  @doc "Broadcasts `message` on `topic`."
  @spec broadcast(String.t(), term()) :: :ok | {:error, term()}
  def broadcast(topic, message), do: Commanded.PubSub.broadcast(Application, topic, message)
end
