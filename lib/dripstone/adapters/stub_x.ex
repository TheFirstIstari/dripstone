defmodule Dripstone.Adapters.StubX do
  @moduledoc "Offline X stub — normalizes `test/fixtures/stub_x_posts.json`."

  @behaviour Dripstone.Adapters

  @fixture ["test", "fixtures", "stub_x_posts.json"]

  @impl true
  def fetch_posts(handle, opts \\ []) when is_binary(handle) do
    with {:ok, raw} <- read_fixture(opts),
         {:ok, items} <- Jason.decode(raw) do
      {:ok, Enum.map(items, &normalize(&1, handle))}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_fixture(opts) do
    path = Keyword.get(opts, :fixture_path, Path.join([File.cwd!() | @fixture]))

    case File.read(path) do
      {:ok, _} = ok -> ok
      {:error, reason} -> {:error, {:fixture_unreadable, reason}}
    end
  end

  defp normalize(%{"id" => id} = item, handle) do
    %{
      id: to_string(id),
      handle: handle,
      text: Map.get(item, "text", ""),
      urls: Map.get(item, "urls", []),
      published_at: parse_time(Map.get(item, "created_at"))
    }
  end

  defp parse_time(nil), do: nil

  defp parse_time(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
