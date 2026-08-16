defmodule Catapult.GuardrailsTest do
  use ExUnit.Case, async: true

  alias Catapult.Guardrails

  defmodule Engine do
    use Catapult.Component, slug: :engine

    def processes do
      [
        {:engine_plain, :local},
        {:engine_bounded, :singleton, max_heap_size: 200_000},
        {:engine_watched, :local, message_queue_alarm_len: 10_000}
      ]
    end
  end

  test "the heap bound is a real process flag, and the VM kills on it" do
    task =
      Task.async(fn ->
        :ok = Guardrails.apply!(Engine, :engine_bounded)
        Process.info(self(), :max_heap_size)
      end)

    assert {:max_heap_size, flag} = Task.await(task)
    assert flag[:size] == 200_000
    assert flag[:kill] == true
    assert flag[:error_logger] == true
  end

  test "the mailbox threshold is declared, not applied — the VM has none to offer" do
    task =
      Task.async(fn ->
        before = Process.info(self(), :max_heap_size)
        :ok = Guardrails.apply!(Engine, :engine_watched)
        {before, Process.info(self(), :max_heap_size)}
      end)

    assert {same, same} = Task.await(task)
    assert Guardrails.declared(Engine, :engine_watched) == [message_queue_alarm_len: 10_000]
    refute :message_queue_alarm_len in Guardrails.enforceable()
  end

  test "a process with no guardrails applies none and says so" do
    assert Guardrails.declared(Engine, :engine_plain) == []
    assert :ok = Guardrails.apply!(Engine, :engine_plain)
  end

  test "guarding a process nobody registered fails where it is written" do
    assert Guardrails.declared(Engine, :engine_ghost) == nil

    assert_raise ArgumentError, ~r/declares no process :engine_ghost in processes\/0/, fn ->
      Guardrails.apply!(Engine, :engine_ghost)
    end
  end
end
