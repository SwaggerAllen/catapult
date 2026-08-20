defmodule Catapult.Engine.Events.ActiveBundleFlipped do
  @moduledoc """
  The active bundle changed on one axis — act (4) of a cutover (v5
  §6, §7.19), recorded as an event on both axes because rule (a) of
  §7.19's blocked-ticket re-resolution is a join between a ticket's
  status history and this timeline, and neither half is answerable
  without the other in the log. Version 1.

  The reducer folds this into `Catapult.Engine.Store
  .ActiveBundleVersion` — the ninth projection (`systems/engine.md`) —
  and consults that projection, in log order, for whichever event
  after this one needs bundle semantics; it never reads `core_dsl`'s
  currently-loaded bundle mid-fold.
  """

  @enforce_keys [:project_id, :axis, :bundle_name, :version, :flip_id]
  @derive Jason.Encoder
  defstruct [:project_id, :axis, :bundle_name, :version, :flip_id]

  @type t :: %__MODULE__{
          project_id: binary(),
          axis: :chain | :workflow,
          bundle_name: String.t(),
          version: String.t(),
          flip_id: binary()
        }
end
