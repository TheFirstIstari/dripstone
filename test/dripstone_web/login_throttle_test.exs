defmodule DripstoneWeb.LoginThrottleTest do
  use ExUnit.Case, async: false

  alias DripstoneWeb.LoginThrottle

  setup do
    LoginThrottle.reset_all()
    :ok
  end

  test "check_and_record allows 5 attempts then throttles" do
    key = "throttle-basic@example.com"

    for _ <- 1..5, do: assert(:ok = LoginThrottle.check_and_record(key))
    assert :throttled = LoginThrottle.check_and_record(key)
    refute LoginThrottle.allowed?(key)
  end

  test "concurrent check_and_record admits at most 5 attempts" do
    key = "throttle-race@example.com"
    for _ <- 1..4, do: LoginThrottle.record(key)

    results =
      1..10
      |> Enum.map(fn _ -> Task.async(fn -> LoginThrottle.check_and_record(key) end) end)
      |> Task.await_many()

    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.count(results, &(&1 == :throttled)) == 9
  end

  test "expired keys are pruned instead of retained" do
    key = "throttle-prune@example.com"
    stale = System.monotonic_time(:millisecond) - 120_000
    :sys.replace_state(LoginThrottle, fn _ -> %{key => [stale]} end)

    assert LoginThrottle.allowed?(key)
    assert :sys.get_state(LoginThrottle) == %{}
  end
end
