defmodule Catapult.Engine.Commands.FlipActiveBundle do
  @moduledoc "Act (4) of a cutover (v5 §6, §7.19): flips the active bundle on one axis."

  @enforce_keys [:project_id, :axis, :bundle_name, :version, :flip_id]
  defstruct [:project_id, :axis, :bundle_name, :version, :flip_id]
end
