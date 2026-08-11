defmodule Catapult.Component do
  @moduledoc """
  The component behaviour (conventions §4): every Catapult component
  adopts it and declares its claims on shared root resources through
  the registry callbacks. The root composer (`Catapult.Component.Composer`)
  aggregates all components and fails on collision — a warning about a
  name collision is a collision that ships.

  Registered names ride the slug spine (conventions §3): a component
  slugged `:engine` claims `engine:*` topics, `:engine_*` queues,
  `[:catapult, :engine, ...]` telemetry, and nothing else.
  """

  @type placement :: :local | :singleton | :sharded

  @doc "The component's slug — the spine every derived name hangs off."
  @callback slug() :: atom()

  @doc "Config surface: env-var specs, prefixed by the slug."
  @callback config() :: [{key :: atom(), env_var :: String.t(), opts :: keyword()}]

  @doc "PubSub topic prefixes claimed (as atoms; rendered `slug:name`)."
  @callback pubsub_topics() :: [atom()]

  @doc "Oban queue names claimed."
  @callback oban_queues() :: [atom()]

  @doc "Telemetry event names claimed (each `[:catapult, slug | rest]`)."
  @callback telemetry_events() :: [[atom()]]

  @doc "Event types (ES components only; conventions §6)."
  @callback events() :: [atom()]

  @doc "Named processes with declared placement (conventions §5)."
  @callback processes() :: [{name :: atom(), placement()}]

  @doc "Idempotent seeds (conventions §6); runs on every deploy."
  @callback seeds() :: :ok

  @doc "Supervision children, composed into the root (conventions §4)."
  @callback children() :: [Supervisor.child_spec() | {module(), term()} | module()]

  @doc "Readiness for the health endpoint (conventions §10)."
  @callback ready?() :: boolean()

  defmacro __using__(opts) do
    slug = Keyword.fetch!(opts, :slug)

    quote do
      @behaviour Catapult.Component
      @catapult_slug unquote(slug)
      import Catapult.Component.API, only: [defexport: 2]

      @impl Catapult.Component
      def slug, do: @catapult_slug

      @impl Catapult.Component
      def config, do: []
      @impl Catapult.Component
      def pubsub_topics, do: []
      @impl Catapult.Component
      def oban_queues, do: []
      @impl Catapult.Component
      def telemetry_events, do: []
      @impl Catapult.Component
      def events, do: []
      @impl Catapult.Component
      def processes, do: []
      @impl Catapult.Component
      def seeds, do: :ok
      @impl Catapult.Component
      def children, do: []
      @impl Catapult.Component
      def ready?, do: true

      defoverridable config: 0,
                     pubsub_topics: 0,
                     oban_queues: 0,
                     telemetry_events: 0,
                     events: 0,
                     processes: 0,
                     seeds: 0,
                     children: 0,
                     ready?: 0

      @doc false
      def __catapult_component__, do: true
    end
  end
end
