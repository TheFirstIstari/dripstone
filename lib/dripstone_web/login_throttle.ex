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

  def start_link(_opts), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  def key(email) when is_binary(email), do: email |> String.trim() |> String.downcase()

  def allowed?(key) do
    Agent.get(__MODULE__, fn attempts ->
      length(recent(Map.get(attempts, key, []))) < @max_attempts
    end)
  end

  def record(key) do
    now = System.monotonic_time(:millisecond)

    Agent.update(__MODULE__, fn attempts ->
      Map.update(attempts, key, [now], &[now | recent(&1)])
    end)
  end

  def reset(key), do: Agent.update(__MODULE__, &Map.delete(&1, key))

  # Test/support helper: clear all counters.
  def reset_all, do: Agent.update(__MODULE__, fn _ -> %{} end)

  defp recent(timestamps) do
    cutoff = System.monotonic_time(:millisecond) - @window_ms
    Enum.filter(timestamps, &(&1 > cutoff))
  end
end
