defmodule Catapult.Foundation.Clock.Fake do
  @moduledoc """
  The test-env clock (conventions §9's determinism requirement):
  returns a fixed instant unless a test overrides it via
  `Application.put_env(:catapult, :foundation_fake_clock, datetime)`.
  """

  @behaviour Catapult.Clock

  @impl Catapult.Clock
  def utc_now do
    Application.get_env(:catapult, :foundation_fake_clock, ~U[2026-01-01 00:00:00.000000Z])
  end
end
