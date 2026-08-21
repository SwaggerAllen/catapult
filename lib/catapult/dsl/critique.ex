defmodule Catapult.Dsl.Critique do
  @moduledoc """
  The optional `critique.yaml` (dsl-syntax.md §15.5): a workflow
  bundle's declaration that the `critique` system status runs, and how
  deep. Fixed, singular path at a workflow bundle's root, sibling to
  `bundle.yaml` — never a glob, since there is exactly one `critique`
  status to configure — layered under `extends:` by same-path replace
  like any other bundle file (`Catapult.Dsl.Extends
  .resolve_content_path/2`), never additively.

  Presence in the loaded union is the whole of what turns the slot on:
  there is deliberately no `enabled:` field, for the same reason a
  gate needs none (dsl-syntax.md §13). Structural parsing only, and
  deliberately thin — no `after:`, no `role:`, nothing that would make
  this look like a review-status declaration of its own: it configures
  the fixed `critique` status (§15.1), it does not declare one.
  """

  alias Catapult.Dsl.Fields

  @enforce_keys [:file]
  defstruct [:file, depth: 0]

  @type t :: %__MODULE__{
          file: String.t(),
          depth: Fields.depth()
        }

  @core_keys ~w(depth)

  @doc "Parses `critique.yaml` from its YAML map."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(file, %{} = raw) do
    where = "critique declaration #{file}"
    {depth, depth_problems} = Fields.depth(raw, where)
    unknown = Fields.unknown_keys(raw, @core_keys, where)

    problems = depth_problems ++ unknown

    if problems == [] do
      {:ok, %__MODULE__{file: file, depth: depth}}
    else
      {:error, problems}
    end
  end

  def parse(file, other) do
    {:error, ["critique declaration #{file} is #{inspect(other)}, expected a YAML mapping"]}
  end
end
