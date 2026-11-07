defmodule Dripstone.Feeds.URL do
  @moduledoc false
  # Helpers for feed link builders. Handles, ids and hosts come from external data,
  # so every path segment is percent-encoded and hosts are validated before use.

  @host ~r/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+\z/

  @doc "Strips the given display prefixes (e.g. `\"@\"`) from a handle."
  @spec bare(term(), [String.t()]) :: String.t()
  def bare(handle, prefixes \\ ["@"])

  def bare(handle, prefixes) when is_binary(handle) do
    handle = String.trim(handle)
    Enum.reduce(prefixes, handle, &String.trim_leading(&2, &1))
  end

  def bare(_handle, _prefixes), do: ""

  @doc "Lowercased host if it is a valid DNS name, otherwise `nil`."
  @spec host(term()) :: String.t() | nil
  def host(value) when is_binary(value) do
    host = value |> String.trim() |> String.downcase()
    if Regex.match?(@host, host), do: host
  end

  def host(_value), do: nil

  @doc """
  Joins `base` with percent-encoded path segments. A segment may be
  `{:prefixed, literal, value}` to keep a literal prefix such as `"@"` unencoded.
  Returns `nil` if the base or any segment value is missing or empty.
  """
  @spec build(String.t() | nil, [term()]) :: String.t() | nil
  def build(nil, _segments), do: nil

  def build(base, segments) do
    if Enum.all?(segments, &present?/1) do
      Enum.map_join([base | Enum.map(segments, &encode/1)], "/", & &1)
    end
  end

  defp present?({:prefixed, literal, value}) when is_binary(literal), do: present?(value)
  defp present?(value), do: is_binary(value) and value != ""

  defp encode({:prefixed, literal, value}), do: literal <> encode(value)
  defp encode(segment), do: URI.encode(segment, &URI.char_unreserved?/1)
end
