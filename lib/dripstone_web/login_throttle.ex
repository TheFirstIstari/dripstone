defmodule DripstoneWeb.LoginThrottle do
  @moduledoc """
  Per-{IP, account} login attempt throttle backed by a stdlib Agent (no new deps).

  Allows 5 attempts per minute per IP + account pair, so one source cannot
  burn another person's budget; a success resets the count.
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

  # Normalizes to an {ip, email} pair; non-binary email maps to a shared
  # bucket so malformed input still counts without creating atoms/keys.
  def key(ip, email) when is_binary(email), do: {normalize_ip(ip), normalize_email(email)}
  def key(ip, _email), do: {normalize_ip(ip), ""}

  def key(email) when is_binary(email), do: {nil, normalize_email(email)}
  def key(_email), do: {nil, ""}

  # Atomic check-and-record: avoids the allowed? -> record race where N
  # concurrent requests at count 4 would all pass. Writes also sweep
  # expired keys once the map exceeds @sweep_threshold.
  def check_and_record(key) do
    now = System.monotonic_time(:millisecond)

    Agent.get_and_update(__MODULE__, fn attempts ->
      case recent(Map.get(attempts, key, [])) do
        timestamps when length(timestamps) >= @max_attempts ->
          {:throttled, Map.put(attempts, key, timestamps)}

        timestamps ->
          attempts = Map.put(attempts, key, [now | timestamps])
          {:ok, maybe_sweep(attempts)}
      end
    end)
  end

  def reset(key), do: Agent.update(__MODULE__, &Map.delete(&1, key))

  # Test/support helper: clear all counters.
  def reset_all, do: Agent.update(__MODULE__, fn _ -> %{} end)

  defp normalize_email(email), do: email |> String.trim() |> String.downcase()

  defp normalize_ip({_, _, _, _} = ip), do: ip
  defp normalize_ip({_, _, _, _, _, _, _, _} = ip), do: ip
  defp normalize_ip(_), do: nil

  defp maybe_sweep(attempts) do
    if map_size(attempts) > @sweep_threshold, do: sweep(attempts), else: attempts
  end

  defp recent(timestamps) do
    cutoff = System.monotonic_time(:millisecond) - @window_ms
    Enum.filter(timestamps, &(&1 > cutoff))
  end

  defp sweep(attempts) do
    Map.reject(attempts, fn {_key, timestamps} -> recent(timestamps) == [] end)
  end
end
