defmodule Catapult.Component.Registries do
  @moduledoc """
  The registry roster as one table (systems/substrate.md): one row per
  name-claiming registry, carrying its entry shape, opts vocabulary,
  spine rule and collision key. Aggregation, the collision report and
  the inventory are each one pass over `rows/0`, so adding a registry
  is an entry rather than a debate — `systems/registry.md`'s idiom for
  artifact kinds, which is the same idiom for the same reason. Twelve
  registries × five properties is a matrix, and hand-writing it as
  twelve validator functions is how a composer becomes the monolith the
  audit refused to be one level up.

  Plural, and not `Catapult.Component.Registry`, because the singular
  reads as the artifact registry this repo also has a system doc for.

  `config/0` is deliberately outside the table: it is the only registry
  with a consumer, a boot half and error messages worth their
  specificity, and `Catapult.Config` keeps them. Absorbing it would
  trade a good report for a uniform one.

  ## The columns

    * `:key` — the callback the entries come from, and the inventory key.
    * `:label` — what a report calls one entry.
    * `:fields` — the positional elements in order, as `name: type`.
      The address is positional; everything said *about* it is opts.
    * `:opts` — the known opts vocabulary, as `name: type`. `[]` means
      the entry carries no opts tail at all.
    * `:required_opts` — opts reported when absent. An opt is not
      optional for sitting in a keyword list: `api_surface/0`'s
      `version:` and `audience:` are required, because the alternative
      is a five-element tuple whose fourth element nobody can count.
    * `:sugar` — whether the opts tail may be omitted (and, on a
      one-field row, the tuple with it). Optional facts get sugar;
      mandatory ones get none.
    * `:spine` — the slug-spine rule, armed wherever a claimed name is
      a global atom. `nil` where there is nothing to check.
    * `:claim` — the collision key *across* components.
    * `:identity` — the duplicate key *within* one component. It
      differs from `:claim` only for `events/0`, where one component
      declaring one type at two versions is ordinary and permanent.

  ## The field and opt types

  `:atom`, `:string`, `:pos_integer`, `:module` (loadable),
  `:check_module` (loadable and implementing `Catapult.Audit.Check`),
  `:crontab` (a non-empty list of `{schedule, worker}` pairs),
  `:telemetry_path`, `:export` (a `{name, arity}` this component
  actually exports through `defexport`), `:route_path`, `:mount_path`
  (relative to an admin root the component does not own),
  `:scope_glob` (relative to the working directory, and reported if it
  climbs out), and `{:one_of, values}` for the closed vocabularies.

  Normalization happens once, here: two accepted spellings are
  affordable only because nothing downstream sees them. Every consumer
  — the collision report, the audit's census, the generators later —
  reads the wide form `normalize/2` returns.
  """

  @classifications [:none, :operational, :customer_content, :personal]
  @audiences [:internal, :public, :partner]
  @placements [:local, :singleton, :sharded]
  @verbs [:get, :post, :put, :patch, :delete]

  @typedoc "One registry's row in the roster."
  @type row :: %{
          key: atom(),
          label: String.t(),
          fields: keyword(),
          opts: keyword(),
          required_opts: [atom()],
          sugar: boolean(),
          spine: {:atom_prefix, atom()} | {:telemetry, atom()} | nil,
          claim: [atom() | {:opt, atom()} | {:route, atom()}],
          identity: [atom() | {:opt, atom()} | {:route, atom()}]
        }

  @typedoc "An entry in the wide form, keyed by the row's field names plus `:opts`."
  @type entry :: %{required(:opts) => keyword(), optional(atom()) => term()}

  @doc """
  Every registry row, in report order.

  A function rather than an attribute because the rows carry the
  vocabularies as data and the inventory reads them at runtime.
  """
  @spec rows() :: [row()]
  def rows do
    [
      row(:pubsub_topics, "pubsub topic", fields: [topic: :atom]),
      row(:oban_queues, "oban queue",
        fields: [queue: :atom],
        opts: [cron: :crontab],
        sugar: true,
        spine: {:atom_prefix, :queue}
      ),
      row(:telemetry_events, "telemetry event",
        fields: [event: :telemetry_path],
        spine: {:telemetry, :event}
      ),
      row(:events, "event type",
        fields: [type: :atom, version: :pos_integer],
        identity: [:type, :version]
      ),
      row(:processes, "process name",
        fields: [name: :atom, placement: {:one_of, @placements}],
        opts: [max_heap_size: :pos_integer, message_queue_alarm_len: :pos_integer],
        sugar: true
      ),
      row(:errors, "error kind",
        fields: [kind: :atom, meaning: :string],
        opts: [remedy: :string, runbook: :string, admin: :string],
        required_opts: [:remedy],
        spine: {:atom_prefix, :kind}
      ),
      row(:externals, "external",
        fields: [name: :atom],
        opts: [
          adapter: :module,
          fake: :module,
          kill_switch: :atom,
          classification: {:one_of, @classifications}
        ],
        required_opts: [:adapter, :fake, :kill_switch, :classification]
      ),
      row(:feature_flags, "feature flag",
        fields: [flag: :atom],
        spine: {:atom_prefix, :flag}
      ),
      row(:permissions, "permission",
        fields: [permission: :atom],
        spine: {:atom_prefix, :permission}
      ),
      row(:api_surface, "api route",
        fields: [function: :export, verb: {:one_of, @verbs}, path: :route_path],
        opts: [version: :string, audience: {:one_of, @audiences}],
        required_opts: [:version, :audience],
        claim: [{:opt, :version}, :verb, {:route, :path}]
      ),
      row(:admin, "admin mount",
        fields: [path: :mount_path, module: :module],
        opts: [label: :string],
        sugar: true
      ),
      row(:policies, "policy check",
        fields: [check: :check_module, scope: :scope_glob],
        opts: [policy: :string],
        required_opts: [:policy],
        claim: [:check, :scope]
      )
    ]
  end

  @doc "The callbacks the roster covers, in report order."
  @spec keys() :: [atom()]
  def keys, do: Enum.map(rows(), & &1.key)

  @doc """
  Normalizes one declared entry into the wide form, or `:error`.

  The wide form is a map of the row's field names plus `:opts` — the
  one place the accepted spellings collapse. A second normalizer
  anywhere is the defect this is trading against.
  """
  @spec normalize(row(), term()) :: {:ok, entry()} | :error
  def normalize(row, declared) do
    with {:ok, values, opts} <- split(row, declared) do
      entry =
        values
        |> Enum.zip(row.fields)
        |> Map.new(fn {value, {name, _type}} -> {name, value} end)
        |> Map.put(:opts, opts)

      {:ok, entry}
    end
  end

  @doc "How this row's entries are spelled, for the malformed-entry report."
  @spec expected_form(row()) :: String.t()
  def expected_form(row) do
    names = Enum.map_join(row.fields, ", ", fn {name, _type} -> to_string(name) end)
    bare = if length(row.fields) == 1, do: names, else: "{#{names}}"

    cond do
      row.opts == [] -> bare
      row.sugar -> "#{bare} or {#{names}, opts}"
      true -> "{#{names}, opts}"
    end
  end

  @doc "The key this entry claims against every other component's."
  @spec claim(row(), entry()) :: term()
  def claim(row, entry), do: key_for(row.claim, entry)

  @doc "The key this entry is a duplicate of within its own component."
  @spec identity(row(), entry()) :: term()
  def identity(row, entry), do: key_for(row.identity, entry)

  @doc """
  Everything wrong with one normalized entry, all at once.

  The spine check runs only when the fields themselves typed, so a
  malformed name is one line rather than two.
  """
  @spec entry_problems(row(), module(), entry()) :: [String.t()]
  def entry_problems(row, component, entry) do
    where = where(row, component, entry)

    case field_problems(row, component, entry, where) do
      [] -> opts_problems(row, entry, where) ++ spine_problems(row, component, entry, where)
      problems -> problems ++ opts_problems(row, entry, where)
    end
  end

  ## The table

  defp row(key, label, spec) do
    fields = Keyword.fetch!(spec, :fields)
    [{first, _type} | _] = fields
    claim = Keyword.get(spec, :claim, [first])

    %{
      key: key,
      label: label,
      fields: fields,
      opts: Keyword.get(spec, :opts, []),
      required_opts: Keyword.get(spec, :required_opts, []),
      sugar: Keyword.get(spec, :sugar, false),
      spine: Keyword.get(spec, :spine),
      claim: claim,
      identity: Keyword.get(spec, :identity, claim)
    }
  end

  ## Spelling

  # No opts tail at all: the entry is its positional elements and
  # nothing else.
  defp split(%{opts: []} = row, declared) do
    with {:ok, values} <- positional(row.fields, declared), do: {:ok, values, []}
  end

  defp split(row, declared) when is_tuple(declared) do
    parts = Tuple.to_list(declared)
    arity = length(row.fields)

    case Enum.split(parts, arity) do
      {values, [opts]} when length(values) == arity ->
        if Keyword.keyword?(opts), do: {:ok, values, opts}, else: :error

      {values, []} when length(values) == arity ->
        if row.sugar, do: {:ok, values, []}, else: :error

      _ ->
        :error
    end
  end

  # The bare one-field spelling — `:engine_work` for a queue — which
  # only a sugared row offers.
  defp split(row, declared) do
    if row.sugar and length(row.fields) == 1, do: {:ok, [declared], []}, else: :error
  end

  defp positional([_one], declared) when not is_tuple(declared), do: {:ok, [declared]}

  defp positional(fields, declared)
       when is_tuple(declared) and tuple_size(declared) == length(fields),
       do: {:ok, Tuple.to_list(declared)}

  defp positional(_fields, _declared), do: :error

  ## Keys

  defp key_for(parts, entry) do
    case Enum.map(parts, &part(&1, entry)) do
      [single] -> single
      many -> List.to_tuple(many)
    end
  end

  defp part({:opt, name}, entry), do: Keyword.get(entry.opts, name)

  # Route identity is the path's shape, not its parameter names:
  # `/projects/:id` and `/projects/:project_id` are one route to any
  # router and two strings to a naive check.
  defp part({:route, name}, entry) do
    case Map.fetch!(entry, name) do
      path when is_binary(path) -> route_shape(path)
      other -> other
    end
  end

  defp part(name, entry), do: Map.fetch!(entry, name)

  defp route_shape(path) do
    path
    |> String.split("/")
    |> Enum.map_join("/", fn
      ":" <> _param -> ":param"
      segment -> segment
    end)
  end

  ## Reporting

  defp where(row, component, entry) do
    [{first, _type} | _] = row.fields
    "#{inspect(component)}'s #{row.label} #{inspect(Map.fetch!(entry, first))}"
  end

  # The `<- [...]` generator filters on pattern mismatch, so a field
  # that typed yields nothing rather than a problem about nothing
  # (Catapult.Config's idiom).
  defp field_problems(row, component, entry, where) do
    for {name, type} <- row.fields,
        reason when is_binary(reason) <- [type_problem(type, Map.fetch!(entry, name), component)] do
      "#{where} has a #{name} that #{reason}"
    end
  end

  defp opts_problems(row, entry, where) do
    known = Keyword.keys(row.opts)

    unknown_opts(entry, where, known) ++
      missing_opts(row, entry, where) ++
      opt_type_problems(row, entry, where)
  end

  defp unknown_opts(entry, where, known) do
    for {opt, _value} <- entry.opts, opt not in known do
      "#{where} carries unknown opt #{inspect(opt)} (known: #{inspect(known)})"
    end
  end

  defp missing_opts(row, entry, where) do
    for opt <- row.required_opts, not Keyword.has_key?(entry.opts, opt) do
      "#{where} is missing required opt #{inspect(opt)}"
    end
  end

  # Unknown opts are `unknown_opts/3`'s line; this types only the ones
  # the row knows, so a typo is one problem rather than two.
  defp opt_type_problems(row, entry, where) do
    for {opt, value} <- entry.opts,
        {:ok, type} <- [Keyword.fetch(row.opts, opt)],
        reason when is_binary(reason) <- [type_problem(type, value, nil)] do
      "#{where} has a #{opt} that #{reason}"
    end
  end

  # The spine check arms wherever a name is a global atom.
  # `pubsub_topics/0` is the exception that proves it: the composer
  # renders `slug:name` from a bare atom, so a prefix there would be
  # the slug written twice.
  defp spine_problems(%{spine: nil}, _component, _entry, _where), do: []

  defp spine_problems(%{spine: {:atom_prefix, field}}, component, entry, where) do
    prefix = "#{component.slug()}_"
    name = entry |> Map.fetch!(field) |> Atom.to_string()

    if String.starts_with?(name, prefix) do
      []
    else
      ["#{where} is off the slug spine (expected #{prefix}*)"]
    end
  end

  defp spine_problems(%{spine: {:telemetry, field}}, component, entry, where) do
    slug = component.slug()

    case Map.fetch!(entry, field) do
      [:catapult, ^slug | _rest] -> []
      _other -> ["#{where} is off the slug spine (expected [:catapult, #{inspect(slug)} | _])"]
    end
  end

  ## Types

  defp type_problem(:atom, value, _component) when is_atom(value) and not is_boolean(value) do
    if is_nil(value), do: "is not an atom", else: nil
  end

  defp type_problem(:atom, _value, _component), do: "is not an atom"

  defp type_problem(:string, value, _component) when is_binary(value), do: nil
  defp type_problem(:string, _value, _component), do: "is not a string"

  defp type_problem(:pos_integer, value, _component) when is_integer(value) and value > 0, do: nil
  defp type_problem(:pos_integer, _value, _component), do: "is not a positive integer"

  defp type_problem({:one_of, allowed}, value, _component) do
    if value in allowed, do: nil, else: "is not one of #{inspect(allowed)}"
  end

  # A fake declared and never written is a hole in the no-network rule
  # (conventions §9), and CI is a better place to find it than the
  # first test that reaches for it.
  defp type_problem(:module, value, _component) do
    cond do
      not is_atom(value) or is_nil(value) -> "is not a module"
      not Code.ensure_loaded?(value) -> "names a module that does not load: #{inspect(value)}"
      true -> nil
    end
  end

  defp type_problem(:check_module, value, component) do
    case type_problem(:module, value, component) do
      nil -> check_behaviour_problem(value)
      reason -> reason
    end
  end

  # A crontab entry points at a *worker*, not at a queue
  # (`Oban.Plugins.Cron`), so one string on a queue entry could say when
  # but never what — and one queue hosting two periodic jobs could not be
  # spelled at all. The queue stays the claimed name and the address; the
  # schedules ride as policy about it (systems/substrate.md).
  defp type_problem(:crontab, value, component) do
    if is_list(value) and value != [] and Enum.all?(value, &crontab_entry?(&1, component)) do
      nil
    else
      "is not a non-empty list of {schedule, worker} pairs"
    end
  end

  defp type_problem(:telemetry_path, value, _component) do
    if is_list(value) and value != [] and Enum.all?(value, &is_atom/1) do
      nil
    else
      "is not a non-empty list of atoms"
    end
  end

  defp type_problem(:export, {name, arity}, component)
       when is_atom(name) and is_integer(arity) and arity >= 0 do
    if {name, arity} in exports(component) do
      nil
    else
      "names #{name}/#{arity}, which this component does not export with defexport"
    end
  end

  defp type_problem(:export, _value, _component), do: "is not a {name, arity} pair"

  defp type_problem(:route_path, value, _component) do
    if is_binary(value) and String.starts_with?(value, "/") do
      nil
    else
      "is not a path beginning with /"
    end
  end

  # An admin entry's path is a segment beneath the admin root, never an
  # absolute `/admin/...`: where the root mounts is the composing
  # application's decision (v5 §2.7).
  defp type_problem(:mount_path, value, _component) do
    cond do
      not is_binary(value) -> "is not a string"
      String.starts_with?(value, "/") -> "is absolute (mounts are relative to the admin root)"
      climbs_out?(value) -> "climbs out of the admin root"
      true -> nil
    end
  end

  # A registration surface that accepted `../../lib/**` would walk back
  # in the cross-project reach `docs/non-goals.md` ruled out, while the
  # audit task's own globs stayed innocent.
  defp type_problem(:scope_glob, value, _component) do
    cond do
      not is_binary(value) -> "is not a string"
      String.starts_with?(value, "/") -> "is absolute (scopes are relative to the audit's cwd)"
      climbs_out?(value) -> "climbs out of the working directory"
      true -> nil
    end
  end

  defp crontab_entry?({schedule, worker}, component) when is_binary(schedule) do
    type_problem(:module, worker, component) == nil
  end

  defp crontab_entry?(_entry, _component), do: false

  defp climbs_out?(path), do: ".." in String.split(path, "/")

  defp check_behaviour_problem(module) do
    if function_exported?(module, :run, 1) do
      nil
    else
      "names #{inspect(module)}, which does not implement Catapult.Audit.Check"
    end
  end

  defp exports(component) do
    if is_atom(component) and function_exported?(component, :__catapult_exports__, 0) do
      component.__catapult_exports__()
    else
      []
    end
  end
end
