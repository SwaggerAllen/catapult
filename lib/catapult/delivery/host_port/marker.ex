defmodule Catapult.Delivery.HostPort.Marker do
  @moduledoc """
  The marker vocabulary, typed and closed, scoped to GitHub PR
  comments only (`systems/delivery.md`'s ORC-31 marker entry). Markers
  exist because GitHub's issue-level PR comments are a store we do not
  own — there is nowhere to put typed data, so protocol state rides in
  prose behind a convention, and one forged or malformed marker
  corrupts a count or a resume silently and much later. That is the
  same reason v5 §7.1's marker rule gave in the first place; it is
  retired everywhere *we* own the store (`docs/ui-spec.md`) and
  survives verbatim here.

  A closed enum of kinds, each with a render function producing the
  exact comment body and a parse function reading one back —
  `{:ok, {kind, payload}} | :not_a_marker` — so no call site builds a
  marker string by interpolation and no call site greps a comment
  body for a substring.

  Phase 4 needs exactly one kind: the scope-violation bounce named in
  v5 §7.5 ("a plane-authored marker comment naming the paths, `Ready
  for rework`"). Later kinds join the same closed enum when their
  phase needs them, not invented ad hoc at whichever call site first
  wants one.

  This module governs the write side only. **The read side needs no
  parser of its own only because the plane never authors a
  line-anchored review comment** — an invariant to keep, not a free
  property (`systems/delivery.md`'s ORC-31 entry spells out the
  consequence if that ever changes). `parse/1`'s one caller today is
  `HostPort`'s own `write_marker_comment/4` implementations, checking
  whether the marker for a given decline is already posted before
  writing a second one — never the harvesting read.
  """

  @type kind :: :scope_violation
  @type payload :: map()

  @kinds [:scope_violation]

  @prefix "<!-- catapult:marker "
  @suffix " -->"
  @header_pattern ~r/^<!-- catapult:marker kind=(?<kind>[a-z_]+) payload=(?<payload>.*) -->$/

  @doc "The closed list of marker kinds this module renders and parses."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc """
  Renders `kind` with `payload` into the exact comment body posted to
  GitHub: a machine-readable header line (kind + JSON payload, inside
  an HTML comment so it renders invisibly) followed by the
  human-readable body.
  """
  @spec render(kind(), payload()) :: String.t()
  def render(:scope_violation, %{paths: paths} = payload) when is_list(paths) do
    header(:scope_violation, payload) <> "\n" <> scope_violation_body(paths)
  end

  @doc """
  Reads a comment body back: `{:ok, {kind, payload}}` if it opens with
  this module's own header and the header names a kind in `kinds/0`,
  `:not_a_marker` for anything else — a comment a human wrote, a
  marker from a kind this build doesn't know, or a header that fails
  to decode. Never raises on untrusted input.
  """
  @spec parse(String.t()) :: {:ok, {kind(), payload()}} | :not_a_marker
  def parse(body) when is_binary(body) do
    with [first_line | _] <- String.split(body, "\n", parts: 2),
         %{"kind" => kind_str, "payload" => payload_str} <-
           Regex.named_captures(@header_pattern, first_line),
         {:ok, kind} <- known_kind(kind_str),
         {:ok, raw_payload} <- Jason.decode(payload_str) do
      {:ok, {kind, atomize_payload(kind, raw_payload)}}
    else
      _ -> :not_a_marker
    end
  end

  defp known_kind(kind_str) do
    kind = String.to_existing_atom(kind_str)
    if kind in @kinds, do: {:ok, kind}, else: :not_a_marker
  rescue
    ArgumentError -> :not_a_marker
  end

  defp atomize_payload(:scope_violation, %{"paths" => paths}), do: %{paths: paths}
  defp atomize_payload(_kind, raw), do: raw

  defp header(kind, payload) do
    @prefix <> "kind=#{kind} payload=#{Jason.encode!(payload)}" <> @suffix
  end

  defp scope_violation_body(paths) do
    """
    **Ready for rework**

    This change touches files outside the ticket's own scope:

    #{Enum.map_join(paths, "\n", &"- `#{&1}`")}
    """
  end
end
