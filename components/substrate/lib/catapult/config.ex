defmodule Catapult.Config do
  @moduledoc """
  The configuration layer that honors `config/0` (conventions §2.2,
  systems/substrate.md): every component declares what it consumes, and
  the composed application derives its configuration surface from those
  declarations. Without this the registry is documentation wearing a
  function head — values read ad hoc from application env, and nothing
  anywhere noticing two readers of one variable disagreeing.

  A declaration is `{key, env_var, opts}`: inert data, readable by the
  audit, by the composer's collision check and by a human reading a
  diff. The opts vocabulary is ours, not a library's:

    * `cast:` — `:string` (the default), `:integer`, `:boolean`, or a
      1-arity function returning `{:ok, value}` or `{:error, reason}`.
      Casts never raise; one that does is reported like any other
      problem rather than taking the report down with it.
    * `default:` — a **string**, cast like any other value. Writing
      `default: "8080"` rather than `8080` is deliberate: the default
      then fails its own cast by name at boot instead of slipping an
      unconverted term past the one definition of what the value means.
    * `required:` — `true` unless a `default:` says otherwise.
      `required: false` resolves an absent value to `nil` and does not
      run the cast.
    * `secret:` — the resolved value is wrapped in a
      `Catapult.Config.Secret`, whose `Inspect` and `String.Chars`
      implementations redact and whose contents come out only through an
      explicit `unwrap/1`. That is v5 §2.2's "never appears in logs or
      error payloads" held by the type rather than chased by a check
      (systems/substrate.md): interpolation, `inspect/1`, a `Logger` call
      and a crash dump are safe by construction, and the audit's residue
      is one hop — an `unwrap` inside a logging call. It changes nothing
      about the *report*, which never names a value at all, flagged or
      not.
    * `external:` — the variable's name is imposed by something outside
      this codebase (`DATABASE_URL`, injected by the host platform), so
      the audit's slug-prefix check does not apply. It confers no
      permission: `external: true` on a name nobody else imposes is a
      lie a reviewer can see, which is the most a declaration can offer.

  ## Two reports, at two times

  Structure — collisions, malformed declarations, an unknown opt, a name
  off the slug spine — is `Catapult.Component.Composer`'s, so CI's audit
  catches it with no environment at all. *Values* are validated here and
  only at boot, because the environment CI has is not the environment
  that matters. Keeping them separate is what lets the build-time half
  be exhaustive instead of best-effort.

  ## All problems at once

  `load!/2` raises a single `LoadError` enumerating every missing and
  every uncastable value — the composer's `CollisionError` style, for
  the composer's reason: N restart cycles to discover N wrong variables
  is hostile to the operator holding the deploy.

  **The report names variables and reasons, never values.** An
  invalid-value message that quotes what it rejected publishes a
  malformed secret into the boot log of the failing deploy, which is the
  log everyone then pastes into a ticket. It costs nothing to hold that
  line for every value rather than only the flagged ones: the operator
  needs to know which variable and why, and already has the value.

  ## Load once, read through one accessor

  Values land in `:persistent_term` under a private key and are read
  with `fetch!/2` — never written into application env, which is more
  inspectable and that is exactly its defect: it would leave the old
  door open, and `Application.get_env` on a component's value would stay
  correct forever, so the ad hoc reading this layer exists to end would
  end only by convention. Write-once-at-boot is the access pattern
  `:persistent_term` is for; the accepted cost is that values are not
  visible from a remote console without calling the accessor.

  The store is keyed by slug, not by module: the slug is the spine every
  other claimed name hangs off (conventions §3), and the composer
  already fails the build on two components sharing one.

  Secret-flagged values are wrapped on the way in rather than on the way
  out, so the store never holds a bare secret either — the accessor's
  contract is the same and the crash-dump surface is one smaller.
  """

  alias Catapult.Config.Secret

  defmodule LoadError do
    @moduledoc "Raised at boot with every configuration problem at once."
    defexception [:message]
  end

  @typedoc "A component's `config/0` entry."
  @type declaration :: {key :: atom(), env_var :: String.t(), opts :: keyword()}

  @typedoc "One declaration with its owner, as `declarations/1` returns it."
  @type composed :: %{
          component: module(),
          slug: atom(),
          key: atom(),
          name: String.t(),
          opts: keyword()
        }

  @store {__MODULE__, :values}

  @known_opts [:cast, :default, :external, :required, :secret]
  @builtin_casts [:string, :integer, :boolean]
  @name_format ~r/\A[A-Z][A-Z0-9_]*\z/

  @doc """
  Loads every declared value through `source`, into the write-once store.

  Idempotent by design rather than by accident: config is read once,
  before the root supervisor starts, and does not change until the next
  boot (docs/non-goals.md). A second call is a no-op, which is what lets
  the entry points that are not the application — a release task, a mix
  task starting the Repo on its own — ask for the load without having to
  know whether the boot already did it.

  Raises `LoadError` listing every problem. Assumes the declarations are
  structurally sound: `Catapult.Component.Composer.validate!/1` is what
  says so, and boot runs it first.
  """
  @spec load!([module()], {module(), term()}) :: :ok
  def load!(components, {source, opts}) do
    if loaded?() do
      :ok
    else
      case resolve(components, {source, opts}) do
        {:ok, values} ->
          :persistent_term.put(@store, values)
          :ok

        {:error, problems} ->
          raise LoadError,
            message: "configuration problems:\n  " <> Enum.join(problems, "\n  ")
      end
    end
  end

  @doc """
  Resolves every declaration against `source` without touching the store.

  The pure half of `load!/2`, and the half worth testing: the store is a
  side effect, the report is the product.
  """
  @spec resolve([module()], {module(), term()}) ::
          {:ok, %{{atom(), atom()} => term()}} | {:error, [String.t()]}
  def resolve(components, {source, opts}) do
    declarations = declarations(components)
    names = declarations |> Enum.map(& &1.name) |> Enum.uniq()

    case source.load(names, opts) do
      {:ok, found} when is_map(found) ->
        per_declaration(declarations, found)

      {:error, problems} when is_list(problems) ->
        # A source that could not be read is the whole report: reporting
        # forty absent values against a file that was never opened
        # buries the one true line (Catapult.Config.Source).
        {:error, Enum.map(problems, &"config source #{inspect(source)}: #{&1}")}

      other ->
        {:error, ["config source #{inspect(source)} returned #{inspect(other)}"]}
    end
  end

  @doc """
  The value declared by `slug` under `key`, cast.

  The one accessor. There is no `get/3` with a runtime default, because
  a default is a property of the declaration and two ways to spell one
  is one too many.

  A declaration carrying `secret: true` returns a
  `Catapult.Config.Secret`; reaching its contents is an explicit
  `Catapult.Config.Secret.unwrap/1` at the call site.
  """
  @spec fetch!(atom(), atom()) :: term()
  def fetch!(slug, key) do
    case :persistent_term.get(@store, :not_loaded) do
      :not_loaded ->
        raise LoadError,
          message:
            "configuration has not been loaded; #{inspect(slug)}.#{key} was read before load!/2"

      values ->
        fetch_loaded!(values, slug, key)
    end
  end

  @doc "Whether the store has been written. Load happens once."
  @spec loaded?() :: boolean()
  def loaded?, do: :persistent_term.get(@store, :not_loaded) != :not_loaded

  @doc "The opts a declaration may carry — the composer checks against this."
  @spec known_opts() :: [atom()]
  def known_opts, do: @known_opts

  @doc """
  Structural problems in one component's `config/0`, all at once.

  The composer's half of the report (see the moduledoc): everything
  checkable without an environment, so the audit catches it in CI.
  """
  @spec declaration_problems(module()) :: [String.t()]
  def declaration_problems(component) do
    entries = component.config()
    prefix = spine_prefix(component.slug())

    duplicate_keys(component, entries) ++
      Enum.flat_map(entries, &entry_problems(component, prefix, &1))
  end

  @doc "The env var names one component declares, for the collision check."
  @spec declared_names(module()) :: [String.t()]
  def declared_names(component) do
    for {_key, name, _opts} <- component.config(), is_binary(name), do: name
  end

  @doc """
  Every declaration `components` compose, each with its owner.

  The composed config surface as data — `Catapult.Component.Composer`'s
  `inventory/1` for the registry that sits outside the roster table. The
  loader reads it, and so does the audit's declared↔read check, which
  needs the component as well as the slug: it reports a dead declaration
  by naming who declared it and which variable to stop setting.

  A non-conforming entry does not match the pattern below and is absent,
  as is a module that is not a component at all;
  `Catapult.Component.Composer.validate!/1` and
  `declaration_problems/1` are what report both, with no environment
  needed and long before a boot. The predicate is spelled here rather
  than borrowed from the composer, which reads this module: one
  `function_exported?/3` is cheaper than a cycle in the graph.
  """
  @spec declarations([module()]) :: [composed()]
  def declarations(components) do
    for component <- components,
        component?(component),
        {key, name, opts} <- component.config(),
        is_atom(key),
        is_binary(name),
        is_list(opts),
        do: %{component: component, slug: component.slug(), key: key, name: name, opts: opts}
  end

  defp component?(module) do
    is_atom(module) and Code.ensure_loaded?(module) and
      function_exported?(module, :__catapult_component__, 0)
  end

  ## Loading

  defp per_declaration(declarations, found) do
    {values, problems} =
      Enum.reduce(declarations, {%{}, []}, fn %{slug: slug, key: key, name: name, opts: opts},
                                              {values, problems} ->
        case value_for(name, opts, found) do
          {:ok, value} ->
            {Map.put(values, {slug, key}, guard(value, opts)), problems}

          {:error, reason} ->
            {values, ["#{name} #{reason} (#{inspect(slug)}.#{key})" | problems]}
        end
      end)

    case problems do
      [] -> {:ok, values}
      _ -> {:error, Enum.reverse(problems)}
    end
  end

  # Unconditionally, including a `required: false` value that resolved to
  # `nil`: a declaration's type should not depend on whether the variable
  # was set, or every consumer needs both spellings.
  defp guard(value, opts) do
    if Keyword.get(opts, :secret, false), do: Secret.wrap(value), else: value
  end

  defp value_for(name, opts, found) do
    case Map.fetch(found, name) do
      # Present-but-empty is present: the host platform can inject an
      # empty variable, and "unset" and "set to nothing" deserve
      # different lines in the report. Whether empty is legal is the
      # cast's business.
      {:ok, raw} -> cast(raw, opts)
      :error -> absent(opts)
    end
  end

  defp absent(opts) do
    cond do
      Keyword.has_key?(opts, :default) -> cast(Keyword.fetch!(opts, :default), opts)
      Keyword.get(opts, :required, true) == false -> {:ok, nil}
      true -> {:error, "is not set"}
    end
  end

  defp cast(raw, opts), do: apply_cast(Keyword.get(opts, :cast, :string), raw)

  defp apply_cast(:string, raw), do: {:ok, raw}

  defp apply_cast(:integer, raw) do
    case Integer.parse(raw) do
      {integer, ""} -> {:ok, integer}
      _ -> {:error, "is not an integer"}
    end
  end

  defp apply_cast(:boolean, "true"), do: {:ok, true}
  defp apply_cast(:boolean, "false"), do: {:ok, false}
  defp apply_cast(:boolean, _raw), do: {:error, ~s(is not "true" or "false")}

  defp apply_cast(fun, raw) when is_function(fun, 1) do
    case fun.(raw) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, "is invalid: #{reason}"}
      other -> {:error, "cast returned #{inspect(other)}, expected {:ok, _} or {:error, _}"}
    end
  rescue
    # The contract is that casts do not raise; one that does is still
    # reported alongside everything else rather than aborting the pass.
    # The exception's *module* only: a message is a channel for the
    # rejected value, and this report never names values.
    exception -> {:error, "cast raised #{inspect(exception.__struct__)}"}
  end

  defp fetch_loaded!(values, slug, key) do
    case Map.fetch(values, {slug, key}) do
      {:ok, value} ->
        value

      :error ->
        raise LoadError,
          message: "#{inspect(slug)} declares no config key #{inspect(key)}"
    end
  end

  ## Structure

  defp spine_prefix(slug), do: "#{String.upcase(Atom.to_string(slug))}_"

  defp duplicate_keys(component, entries) do
    entries
    |> Enum.flat_map(fn
      {key, _name, _opts} when is_atom(key) -> [key]
      _ -> []
    end)
    |> Enum.frequencies()
    |> Enum.filter(fn {_key, count} -> count > 1 end)
    |> Enum.map(fn {key, _count} ->
      "#{inspect(component)} declares config key #{inspect(key)} more than once"
    end)
  end

  defp entry_problems(component, prefix, {key, name, opts})
       when is_atom(key) and is_binary(name) and is_list(opts) do
    if Keyword.keyword?(opts) do
      name_problems(component, prefix, name, opts) ++ opts_problems(component, name, opts)
    else
      ["#{inspect(component)}'s #{name} opts are not a keyword list"]
    end
  end

  defp entry_problems(component, _prefix, entry) do
    [
      "#{inspect(component)} has a malformed config declaration #{inspect(entry)} " <>
        "(expected {key, \"ENV_VAR\", opts})"
    ]
  end

  defp name_problems(component, prefix, name, opts) do
    cond do
      not Regex.match?(@name_format, name) ->
        ["#{inspect(component)}'s #{inspect(name)} is not a SCREAMING_SNAKE env var name"]

      Keyword.get(opts, :external, false) ->
        []

      not String.starts_with?(name, prefix) ->
        [
          "#{inspect(component)}'s #{name} is off the slug spine (expected #{prefix}*; " <>
            "a name imposed from outside is legal with external: true)"
        ]

      true ->
        []
    end
  end

  defp opts_problems(component, name, opts) do
    where = "#{inspect(component)}'s #{name}"

    unknown_opts(where, opts) ++
      boolean_opts(where, opts) ++
      default_opt(where, opts) ++
      cast_opt(where, opts)
  end

  defp unknown_opts(where, opts) do
    for {opt, _value} <- opts, opt not in @known_opts do
      "#{where} carries unknown config opt #{inspect(opt)} (known: #{inspect(@known_opts)})"
    end
  end

  # The `<- [Keyword.fetch(...)]` generator filters on pattern mismatch,
  # so an absent opt yields nothing rather than a problem about its type.
  defp boolean_opts(where, opts) do
    for opt <- [:secret, :required, :external],
        {:ok, value} <- [Keyword.fetch(opts, opt)],
        not is_boolean(value) do
      "#{where} has a non-boolean #{opt}: #{inspect(value)}"
    end
  end

  defp default_opt(where, opts) do
    cond do
      not Keyword.has_key?(opts, :default) ->
        []

      not is_binary(Keyword.fetch!(opts, :default)) ->
        [
          "#{where} has a non-string default #{inspect(Keyword.fetch!(opts, :default))} " <>
            "(defaults go through the declared cast, like every other value)"
        ]

      Keyword.get(opts, :required, true) == false ->
        ["#{where} declares both a default and required: false — pick one"]

      true ->
        []
    end
  end

  defp cast_opt(where, opts) do
    case Keyword.fetch(opts, :cast) do
      :error ->
        []

      {:ok, cast} when cast in @builtin_casts ->
        []

      {:ok, cast} ->
        if is_function(cast, 1) do
          []
        else
          [
            "#{where} has an unusable cast #{inspect(cast)} " <>
              "(expected one of #{inspect(@builtin_casts)} or a 1-arity function)"
          ]
        end
    end
  end
end
