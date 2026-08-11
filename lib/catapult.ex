defmodule Catapult do
  @moduledoc """
  The top-level boundary. One coarse boundary today; per-system
  boundaries (engine, dsl, generation, delivery, ... — see systems/)
  carve out of it as those systems land, per conventions §4. The
  boundary compiler is in the gate set from day one so the carving is
  enforced the moment it starts.
  """
  use Boundary, deps: [], exports: []
end
