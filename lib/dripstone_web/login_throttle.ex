defmodule DripstoneWeb.LoginThrottle do
  @moduledoc """
  Per-account login attempt throttle backed by a stdlib Agent (no new deps).

  Allows 5 attempts per minute per account; a success resets the count.
  Password login and magic-link requests both count as attempts.

  shortcut: single-node memory only, lost on restart; move to a shared
  store when running more than one node.
  """
  use Agent

  @window_ms 60_000
  @max_attempts 5
  # Bounds memory when attackers cycle random emails: once the map exceeds
  # this, a write also sweeps keys whose attempts all expired.
  @sweep_threshold 1_000

  def start_link(_opts), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  def key(email) when is_binary(email), do: email |> String.trim() |> String.downcase()

  def allowed?(key) do
    Agent.get_and_update(__MODULE__, fn attempts ->
      case recent(Map.get(attempts, key, [])) do
        [] -> {true, Map.delete(attempts, key)}
        timestamps -> {length(timestamps) < @max_attempts, Map.put(attempts, key, timestamps)}
      end
    end)
  end

  # Atomic check-and-record: avoids the allowed? -> record race where N
  # concurrent requests at count 4 would all pass.
  def check_and_record(key) do
    now = System.monotonic_time(:millisecond)

    Agent.get_and_update(__MODULE__, fn attempts ->
      case recent(Map.get(attempts, key, [])) do
        timestamps when length(timestamps) >= @max_attempts ->
          {:throttled, Map.put(attempts, key, timestamps)}

        timestamps ->
          {:ok, Map.put(attempts, key, [now | timestamps])}
      end
    end)
  end

  def record(key) do
    now = System.monotonic_time(:millisecond)

    Agent.update(__MODULE__, fn attempts ->
      attempts = Map.put(attempts, key, [now | recent(Map.get(attempts, key, []))])
      if map_size(attempts) > @sweep_threshold, do: sweep(attempts), else: attempts
    end)
  end

  def reset(key), do: Agent.update(__MODULE__, &Map.delete(&1, key))

  # Test/support helper: clear all counters.
  def reset_all, do: Agent.update(__MODULE__, fn _ -> %{} end)

  defp recent(timestamps) do
    cutoff = System.monotonic_time(:millisecond) - @window_ms
    Enum.filter(timestamps, &(&1 > cutoff))
  end

  defp sweep(attempts) do
    Map.reject(attempts, fn {_key, timestamps} -> recent(timestamps) == [] end)
  end
end
