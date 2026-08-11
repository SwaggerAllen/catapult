defmodule Catapult.Repo do
  @moduledoc """
  The one Repo (conventions §6): stores own schemas and queries, never
  connections. Owned by the foundation.
  """
  use Ecto.Repo, otp_app: :catapult, adapter: Ecto.Adapters.Postgres
end
