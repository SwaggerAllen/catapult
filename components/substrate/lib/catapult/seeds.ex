defmodule Catapult.Seeds do
  @moduledoc """
  The seeds runner (conventions §6): every component's `seeds/0`, in
  component order, idempotent by construction — there is no
  fresh-database moment; this runs against live state on every deploy.
  Invoked from the release task.
  """

  alias Catapult.Component.Composer

  def run(components), do: Composer.run_seeds(components)
end
