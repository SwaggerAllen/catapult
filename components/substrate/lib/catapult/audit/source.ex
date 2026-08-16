defmodule Catapult.Audit.Source do
  @moduledoc """
  One source file, parsed once, with its comments (systems/substrate.md's
  enforcement roster): the shared half of every AST-grade
  `Catapult.Audit.Check`, so a check says what a violation *is* and says
  nothing about reading files, honouring escapes or formatting a report.

  ## Why the AST rather than the line

  A grep for a banned call matches the ban's own name in a docstring, in
  a test asserting the ban works, and in the prose explaining it — which
  is why the checks this replaces had to be *stated* rather than spelled.
  At AST grade a string literal is a string literal: the prose can name
  the call it forbids, which is what `Catapult.Clock`'s moduledoc now
  does.

  ## `catapult:allow` is a comment the parser found

  The tag stays in a comment, because the violations are lines inside
  function bodies and there is nowhere else for a line-grained escape to
  live. What changed is who reads it:
  `Code.string_to_quoted_with_comments/2` yields comments with their line
  numbers, so the tag is matched against a *comment* rather than against
  a substring of a source line — and an allow tag written inside a string
  literal excuses nothing, which is the symmetric half of the bug the AST
  grade was adopted for. A ban that no longer false-positives on a
  literal must also stop honouring an escape hiding in one, or the escape
  becomes the new false positive.

  The span is unchanged (ORC-30): the offending line, or the comment line
  directly above it, and no other. Comment line numbers are exactly what
  that span was always about.

  ## An escape that excuses nothing is itself a problem

  A tag covering no violation is reported. An escape list nobody prunes
  is how the next reader learns the ban is negotiable, and this repo has
  already chosen the other shape once — Hex warns that an
  `ignore_advisories` entry matching nothing can be removed, so the
  acknowledgement expires by itself. Same property, same reason. It is
  free only at this grade: a grep cannot tell an idle tag from one whose
  violation it failed to match.

  ## The report format is part of the contract

  A problem that names a location spells it `path:line: message`. That is
  what the greps already emitted, and it is what a `Credo.Check` wrapper
  delegating to `run/1` needs in order to place a finding in an editor —
  the priced reversal of hosting these checks here rather than on Credo
  (docs/non-goals.md).

  ## A file that does not parse is a problem, not a skip

  The audit compiles first, so an unparseable file is normally
  unreachable; a check run on its own must still fail closed, because a
  ban that silently skips what it cannot read is a gate that reports
  clean on exactly the file somebody broke.
  """

  @enforce_keys [:path, :ast, :comments]
  defstruct [:path, :ast, :comments]

  @typedoc "A parsed file: its path, its quoted form and its comments."
  @type t :: %__MODULE__{path: String.t(), ast: Macro.t(), comments: [map()]}

  @typedoc "One violation, as the line it sits on and what is wrong with it."
  @type finding :: {pos_integer(), String.t()}

  @doc """
  Every problem `finder` reports under `scope`, as report lines.

  `scope` is a working-directory-relative glob (the `policies/0`
  contract); `tag` is the bare check name a `catapult:allow` comment
  names. The finder sees a parsed file and returns findings; escapes,
  idle escapes and formatting are this function's.
  """
  @spec scan(String.t(), String.t(), (t() -> [finding()])) :: [String.t()]
  def scan(scope, tag, finder) do
    scope
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn path ->
      case read(path) do
        {:ok, source} -> report(source, tag, finder.(source))
        {:error, problem} -> [problem]
      end
    end)
  end

  @doc """
  Parses one file into a source, or reports why it could not be.

  Public because the checks that need more than one pass over a tree —
  the roster's declared↔applied and declared↔constructed pairs — read the
  same files the file-scoped checks do, and a second reader would be a
  second answer to what a comment means.
  """
  @spec read(String.t()) :: {:ok, t()} | {:error, String.t()}
  def read(path) do
    case File.read(path) do
      {:ok, text} -> parse(path, text)
      {:error, reason} -> {:error, "#{path}: cannot be read (#{:file.format_error(reason)})"}
    end
  end

  @doc """
  Everything `fun` returns for any node of `ast`, in source order.

  A prewalk with the accumulator spelled once: a check that wrote its own
  would be writing traversal rather than a rule, and the rule is the only
  part of a check worth reading.
  """
  @spec collect(Macro.t(), (Macro.t() -> [term()])) :: [term()]
  def collect(ast, fun) do
    {_ast, found} = Macro.prewalk(ast, [], fn node, acc -> {node, acc ++ fun.(node)} end)
    found
  end

  @doc """
  The line a node sits on, or `0` when the parser recorded none.

  Zero rather than `nil` so a report line is always spellable: a finding
  with no line is still a finding, and a `path:0:` prefix says exactly
  that to a reader and to a wrapper parsing it.
  """
  @spec line(Macro.t()) :: non_neg_integer()
  def line({_form, meta, _args}) when is_list(meta), do: Keyword.get(meta, :line, 0)
  def line(_node), do: 0

  @doc """
  Whether an alias node names `module`, ignoring an `Elixir.` prefix.

  `DateTime`, `Elixir.DateTime` and `:"Elixir.DateTime"` are one module
  and three quoted forms, and a check comparing the first spelling only
  is a ban with two spellings that evade it.
  """
  @spec alias?(Macro.t(), atom()) :: boolean()
  def alias?({:__aliases__, _meta, parts}, module) when is_list(parts) do
    List.last(parts) == module
  end

  def alias?(atom, module) when is_atom(atom) and not is_nil(atom) do
    atom == Module.concat([module])
  end

  def alias?(_node, _module), do: false

  ## Parsing

  defp parse(path, text) do
    {ast, comments} = Code.string_to_quoted_with_comments!(text, file: path)
    {:ok, %__MODULE__{path: path, ast: ast, comments: comments}}
  rescue
    error ->
      line = if is_map(error), do: Map.get(error, :line, 0), else: 0
      {:error, "#{path}:#{line}: does not parse (#{describe(error)})"}
  end

  defp describe(error) do
    case error do
      %{description: description} when is_binary(description) -> description
      other -> Exception.message(other)
    end
  end

  ## Escapes and the report

  defp report(source, tag, findings) do
    tagged = tagged_lines(source, tag)
    violated = MapSet.new(findings, fn {line, _message} -> line end)

    unallowed(source, findings, tagged) ++ idle(source, tag, tagged, violated)
  end

  # A tag on line n covers n and n + 1: the offending line, or the
  # comment line directly above it.
  defp tagged_lines(source, tag) do
    marker = "catapult:allow #{tag}"

    for %{line: line, text: text} <- source.comments,
        String.contains?(text, marker),
        into: MapSet.new(),
        do: line
  end

  defp unallowed(source, findings, tagged) do
    for {line, message} <- findings,
        not MapSet.member?(tagged, line),
        not MapSet.member?(tagged, line - 1) do
      "#{source.path}:#{line}: #{message}"
    end
  end

  defp idle(source, tag, tagged, violated) do
    for line <- Enum.sort(tagged),
        not MapSet.member?(violated, line),
        not MapSet.member?(violated, line + 1) do
      "#{source.path}:#{line}: catapult:allow #{tag} excuses nothing " <>
        "on this line or the next (remove it)"
    end
  end
end
