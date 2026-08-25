defmodule Catapult.Delivery.FlagSetWorker do
  @moduledoc """
  The outbox worker for a container's aggregated flag flip (v5 §7.1's
  intent → **idempotent effect** → observed completion; §7.8).

  A flag flip is an external effect exactly like a GitHub call, so it
  may not share a transaction with an event. The shape, and each part's
  reason:

  * `Catapult.Engine.Events.FlagSetFlipRequested` is already in the log
    before this job is enqueued — **intent first**, so an effect that
    happens and is never recorded heals by re-observation rather than
    vanishing.
  * This worker performs the enable through
    `Catapult.Delivery.FlagSet`, which the port requires to be
    idempotent — which is what makes an Oban retry safe.
  * `Catapult.Engine.Commands.RecordFlagSetFlip` is dispatched only
    **after** the port returns `:ok`. The log never says "done" on the
    plane's own word.

  A failed enable returns an error, so Oban retries; the container
  stays visibly at `:requested` in the meantime, which is precisely v5
  §7.1's "intent-without-effect is visible and escalates" rather than a
  milestone quietly reading as lit.

  Uniqueness is keyed on the request rather than the container: a
  second flip request for the same container is rejected at the
  aggregate (v5 §7.1 admits one intent), so a duplicate job can only
  mean a re-enqueue of the same request, which is exactly what should
  collapse.
  """

  use Oban.Worker,
    queue: :delivery_flag_flip,
    unique: [period: :infinity, keys: [:request_id], states: :incomplete]

  require Logger

  alias Catapult.Delivery.FlagSet
  alias Catapult.Engine.Commands.RecordFlagSetFlip
  alias Catapult.Engine.Router

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "project_id" => project_id,
          "container_id" => container_id,
          "request_id" => request_id,
          "flags" => flags
        }
      }) do
    case FlagSet.enable(flags) do
      :ok ->
        record(project_id, container_id, request_id, flags)

      {:error, reason} ->
        Logger.warning(
          "flag set flip for container #{container_id} did not complete: #{inspect(reason)}",
          component: :delivery
        )

        {:error, reason}
    end
  end

  @doc "Enqueues the effect for a recorded intent."
  @spec enqueue(binary(), binary(), binary(), [String.t()]) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(project_id, container_id, request_id, flags) do
    %{
      project_id: project_id,
      container_id: container_id,
      request_id: request_id,
      flags: flags
    }
    |> new()
    |> Oban.insert()
  end

  defp record(project_id, container_id, request_id, flags) do
    command = %RecordFlagSetFlip{
      project_id: project_id,
      container_id: container_id,
      request_id: request_id,
      flags: flags
    }

    case Router.dispatch(command, consistency: :strong) do
      :ok ->
        :ok

      # The aggregate already holds a completion for this request:
      # the effect landed and was recorded on an earlier attempt, and
      # this is the re-delivery healing itself. Nothing left to do,
      # and nothing wrong — returning an error would retry forever.
      {:error, {:engine_flag_flip_not_requested, _details}} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
