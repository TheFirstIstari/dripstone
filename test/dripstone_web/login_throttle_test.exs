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
    assert :throttled = LoginThrottle.check_and_record(key)
  end

  test "concurrent check_and_record admits at most 5 attempts" do
    key = "throttle-race@example.com"
    for _ <- 1..4, do: assert(:ok = LoginThrottle.check_and_record(key))

    results =
      1..10
      |> Enum.map(fn _ -> Task.async(fn -> LoginThrottle.check_and_record(key) end) end)
      |> Task.await_many()

    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.count(results, &(&1 == :throttled)) == 9
  end

  test "expired attempts fall out of the window" do
    key = "throttle-expiry@example.com"
    stale = System.monotonic_time(:millisecond) - 120_000
    :sys.replace_state(LoginThrottle, fn _ -> %{key => [stale, stale, stale, stale, stale]} end)

    for _ <- 1..5, do: assert(:ok = LoginThrottle.check_and_record(key))
    assert :throttled = LoginThrottle.check_and_record(key)
  end

  test "budgets are per IP: one source cannot burn another's" do
    email = "victim-#{System.unique_integer([:positive])}@example.com"

    for _ <- 1..5,
        do: assert(:ok = LoginThrottle.check_and_record(LoginThrottle.key({127, 0, 0, 1}, email)))

    assert :throttled = LoginThrottle.check_and_record(LoginThrottle.key({127, 0, 0, 1}, email))
    assert :ok = LoginThrottle.check_and_record(LoginThrottle.key({10, 0, 0, 2}, email))
  end

  test "non-binary email maps to a shared bucket without crashing" do
    for _ <- 1..5,
        do: assert(:ok = LoginThrottle.check_and_record(LoginThrottle.key({127, 0, 0, 1}, nil)))

    assert :throttled = LoginThrottle.check_and_record(LoginThrottle.key({127, 0, 0, 1}, nil))
  end

  test "writes sweep expired keys once over threshold" do
    stale = System.monotonic_time(:millisecond) - 120_000

    big =
      for n <- 1..1_001,
          into: %{},
          do: {LoginThrottle.key({127, 0, 0, 1}, "sweep-#{n}@example.com"), [stale]}

    :sys.replace_state(LoginThrottle, fn _ -> big end)

    assert :ok =
             LoginThrottle.check_and_record(
               LoginThrottle.key({127, 0, 0, 1}, "fresh@example.com")
             )

    assert map_size(:sys.get_state(LoginThrottle)) == 1
  end
end
