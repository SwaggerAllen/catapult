defmodule Catapult.Dsl.Extension do
  @moduledoc """
  The platform surface (dsl-syntax.md §12, v5 §9): a platform-shipped
  module (never bundle content) registers annotation namespaces,
  declaration kinds, generator types, context sources and enforcement
  profiles here. The core is frozen; this is where growth happens
  (`systems/core_dsl.md`).

  Every registry callback keeps an overridable empty default, the same
  no-optional-callbacks discipline `Catapult.Component` uses and for
  the same reason: incremental adoption is what the default already
  buys, and an optional callback would only add a
  `function_exported?/3` guard at every call site.

  No extension modules are registered by Phase 3's dialects beyond
  `Catapult.Dsl.Core` itself (`systems/core_dsl.md`'s Initial vs
  Target) — delivery's own annotations, generator types and context
  sources arrive with the delivery system. A bundle naming one before
  then gets exactly the `annotation namespace ... is not installed`
  error §12 promises, which is the intended failure mode rather than a
  gap.
  """

  @typedoc "One annotation namespace: the top-level tier key it governs, and its validator."
  @type namespace :: {name :: String.t(), validator :: (term() -> [String.t()])}

  @typedoc "One declaration kind this extension adds (a new bundle file type)."
  @type declaration_kind :: String.t()

  @typedoc "One generator type this extension adds, beyond dsl-syntax.md §3.2's closed set."
  @type generator_type :: String.t()

  @typedoc "One context-source kind this extension adds, beyond `self`/`input`/`ticket`."
  @type context_source :: String.t()

  @typedoc "One enforcement profile this extension binds (`codegen: restricted`, ...)."
  @type enforcement_profile :: String.t()

  @doc "Annotation namespaces this extension registers, each with a validator."
  @callback namespaces() :: [namespace()]

  @doc "New declaration kinds (bundle file types) this extension adds."
  @callback declaration_kinds() :: [declaration_kind()]

  @doc "Generator types this extension adds beyond §3.2's closed set."
  @callback generator_types() :: [generator_type()]

  @doc "Context-source kinds this extension adds beyond `self`/`input`/`ticket`."
  @callback context_sources() :: [context_source()]

  @doc "Enforcement profiles this extension binds."
  @callback enforcement_profiles() :: [enforcement_profile()]

  defmacro __using__(_opts) do
    quote do
      @behaviour Catapult.Dsl.Extension

      @impl Catapult.Dsl.Extension
      def namespaces, do: []
      @impl Catapult.Dsl.Extension
      def declaration_kinds, do: []
      @impl Catapult.Dsl.Extension
      def generator_types, do: []
      @impl Catapult.Dsl.Extension
      def context_sources, do: []
      @impl Catapult.Dsl.Extension
      def enforcement_profiles, do: []

      defoverridable namespaces: 0,
                     declaration_kinds: 0,
                     generator_types: 0,
                     context_sources: 0,
                     enforcement_profiles: 0
    end
  end
end
