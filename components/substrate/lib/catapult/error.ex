defmodule Catapult.Error do
  @moduledoc """
  A component's error struct, built from its `errors/0` registry
  (v5 §2.2, conventions §8):

      defmodule Engine.Error do
        @moduledoc "Engine's boundary failure vocabulary."
        use Catapult.Error, component: Engine
      end

  and `{:error, %Engine.Error{kind: :engine_grammar_invalid}}` is the
  spelling at the boundary, unchanged — callers still match on the
  struct, and the meaning and remedy they would otherwise repeat at every
  construction site come from the declaration.

  ## Why the registry rather than an AST pass

  §2.14 asks for declared↔constructed both ways. The expensive direction
  is a check hunting `kind:` keys, which is a check guessing at what
  construction looks like: it would have to know every spelling of a
  struct literal, a `struct/2` call and a builder, and it would be wrong
  about the next one. The cheap direction is to make construction go
  through something the registry answers. `new/2` resolves its kind
  against `errors/0` and raises on anything the component did not
  declare, so the vocabulary a caller can build is the vocabulary the
  composer validated — and the meaning, remedy, runbook and admin link
  ride along rather than being copied.

  What is left for the audit is the direction no constructor can see: a
  kind declared and never constructed, which is dead vocabulary in a
  catalog operators read. That check is `mix catapult.audit`'s.

  ## The grade, stated rather than implied

  Two things this is *not*, both worth naming because the alternative is
  a reader assuming them:

    * **Construction-time, not compile-time.** Elixir validates a struct
      literal's *keys* at compile time and never its values, so no
      generator can make `%Engine.Error{kind: :invented}` a compile
      error. The residue is one narrow shape — a hand-built literal that
      bypasses `new/2` — rather than the open set an AST pass would have
      had to cover, and writing one means writing the module, the field
      and the atom by hand, which is a different act from forgetting to
      register.
    * **Resolved at runtime, deliberately.** Reading `errors/0` while
      compiling the error module would make `Engine.Error` wait for
      `Engine` — and conventions §8's own spelling has `Engine`
      constructing `%Engine.Error{}`, which makes `Engine` wait for
      `Engine.Error`. That is a compile cycle and a deadlocked build, on
      the canonical usage, for a check the previous paragraph says is not
      available anyway. `xref`'s cycle prohibition is already a hard gate
      (conventions §2); a mechanism whose adoption trips it is not a
      mechanism.

  ## Remedy presence is not re-checked here

  `remedy:` is required by the registry row, so the composer has already
  failed the build on a kind without one (ORC-22). The struct carries it
  from the declaration rather than re-deriving it, which is what keeps
  the declaration the single copy.

  ## The catalog is not a file

  The generated error catalog is a rendering of the inventory on demand
  and never something committed (docs/non-goals.md's
  no-hand-maintained-inventories rule). It ships with the docs-site
  composition, which conventions §13 defers.
  """

  @fields [:kind, :meaning, :remedy, :runbook, :admin, :details]

  @doc "The struct fields every component error carries, in order."
  @spec fields() :: [atom()]
  def fields, do: @fields

  @doc """
  Builds `kind` for `component`, or raises naming the declared vocabulary.

  The generated `new/2` delegates here so the resolution rule has one
  implementation rather than one per adopting module.
  """
  @spec build!(module(), module(), atom(), keyword()) :: struct()
  def build!(struct_module, component, kind, details) do
    case Enum.find(declared(component), &match?({^kind, _meaning, _opts}, &1)) do
      {^kind, meaning, opts} ->
        struct!(struct_module,
          kind: kind,
          meaning: meaning,
          remedy: Keyword.get(opts, :remedy),
          runbook: Keyword.get(opts, :runbook),
          admin: Keyword.get(opts, :admin),
          details: details
        )

      nil ->
        raise ArgumentError,
              "#{inspect(kind)} is not a kind #{inspect(component)} declares in errors/0 " <>
                "(declared: #{inspect(kinds(component))})"
    end
  end

  @doc "The kinds `component` declares, in declaration order."
  @spec kinds(module()) :: [atom()]
  def kinds(component) do
    for {kind, _meaning, _opts} <- declared(component), do: kind
  end

  # A malformed entry is the composer's line, in full and alongside
  # everything else wrong with the roster; here it is only skipped, so a
  # broken declaration cannot become a half-built error at a boundary.
  defp declared(component) do
    for {kind, meaning, opts} <- component.errors(),
        is_atom(kind) and is_binary(meaning) and is_list(opts),
        do: {kind, meaning, opts}
  end

  defmacro __using__(opts) do
    component = Keyword.fetch!(opts, :component)

    quote do
      @catapult_error_component unquote(component)

      @enforce_keys [:kind]
      defstruct unquote(@fields)

      @typedoc "One of the component's declared boundary failures."
      @type t :: %__MODULE__{
              kind: atom(),
              meaning: String.t(),
              remedy: String.t(),
              runbook: String.t() | nil,
              admin: String.t() | nil,
              details: keyword()
            }

      @doc "The component whose `errors/0` this struct speaks for."
      @spec component() :: module()
      def component, do: @catapult_error_component

      @doc "Every kind the component declares, in declaration order."
      @spec kinds() :: [atom()]
      def kinds, do: Catapult.Error.kinds(@catapult_error_component)

      @doc """
      Builds a declared error.

      `details` is caller context — identifiers, counts, the scope the
      failure happened in — and never a value the registry already
      carries, nor a secret (`Catapult.Config.Secret`).
      """
      @spec new(atom(), keyword()) :: t()
      def new(kind, details \\ []) do
        Catapult.Error.build!(__MODULE__, @catapult_error_component, kind, details)
      end
    end
  end
end
