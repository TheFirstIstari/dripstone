defmodule Dripstone.Adapters.StubReddit do
  @moduledoc "Offline Reddit stub — normalizes `test/fixtures/stub_reddit_posts.json`."

  @behaviour Dripstone.Adapters

  @fixture ["test", "fixtures", "stub_reddit_posts.json"]

  @impl true
  def fetch_posts(handle, opts \\ []) when is_binary(handle) do
    with {:ok, raw} <- Dripstone.Adapters.read_fixture(@fixture, opts),
         {:ok, items} <- Jason.decode(raw) do
      {:ok, Enum.map(items, &normalize(&1, handle))}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize(%{"id" => id} = item, handle) do
    text =
      [Map.get(item, "title", ""), Map.get(item, "selftext", "")]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    urls =
      case Map.get(item, "url") do
        nil -> []
        "" -> []
        u -> [u]
      end

    %{
      id: to_string(id),
      handle: handle,
      text: text,
      urls: urls,
      published_at: parse_time(Map.get(item, "created_utc"))
    }
  end

  defp parse_time(nil), do: nil
  defp parse_time(i) when is_integer(i), do: DateTime.from_unix!(i)

  defp parse_time(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
