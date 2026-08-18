defmodule Catapult.Dsl.Error do
  @moduledoc """
  The DSL loader's boundary failure vocabulary (conventions §8).

  The owning component is derived from `__MODULE__` rather than
  spelled `component: Catapult.Dsl` — conventions §8's canonical
  literal — because a literal alias here is a source-level reference
  the compiler tracks, and `Catapult.Dsl`'s boundary export
  constructs this struct directly, which is exactly the two-file
  cycle `mix xref graph --format cycles --fail-above 0` refuses
  (conventions §2; unlike the compile-time cycle `Catapult.Error`'s
  own moduledoc already reasons about, this one is a runtime-edge
  cycle the unlabeled gate still counts). The derivation is mechanical
  and needs no name kept in sync: this module is always
  `<Component>.Error` on the naming spine (conventions §3).
  """
  use Catapult.Error, component: __MODULE__ |> Module.split() |> Enum.drop(-1) |> Module.concat()
end
