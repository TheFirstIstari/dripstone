defmodule Dripstone.Adapters.Bluesky do
  @moduledoc """
  Real Bluesky fetcher behind the shared `fetch_posts(handle, opts)` behaviour.

  Reads an account's recent posts from the public AppView
  (`https://public.api.bsky.app/xrpc`), with no authentication, through
  `Dripstone.Adapters.Polite` (per-host spacing, robots.txt, 429 back-off).
  Bluesky's robots.txt allows crawling the public API and asks for only "a handful"
  of concurrent requests.

  Posts come back canonical: `%{id, handle, text, urls, published_at}`. `id` is the
  post's record key, `urls` are its link facets and external embed, and reposts of
  other accounts' posts are skipped. `profiles/2` resolves DIDs to handles for
  discovery.
  """

  @behaviour Dripstone.Adapters

  alias Dripstone.Adapters.Polite

  @base "https://public.api.bsky.app/xrpc"
  @default_limit 30

  @impl true
  def fetch_posts(handle, opts \\ []) when is_binary(handle) do
    query =
      URI.encode_query(%{
        "actor" => actor(handle),
        "limit" => Keyword.get(opts, :limit, @default_limit),
        "filter" => "posts_no_replies"
      })

    case Polite.get("#{@base}/app.bsky.feed.getAuthorFeed?#{query}", polite_opts(opts)) do
      {:ok, %{body: %{"feed" => feed}}} when is_list(feed) ->
        {:ok, feed |> Enum.reject(&Map.has_key?(&1, "reason")) |> Enum.flat_map(&post/1)}

      {:ok, _response} ->
        {:error, :bad_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Resolves up to 25 DIDs (or handles) to `%{did, handle, display_name, created_at}`.
  """
  @spec profiles([String.t()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def profiles(actors, opts \\ []) when is_list(actors) and length(actors) <= 25 do
    query = actors |> Enum.map(&{"actors", &1}) |> URI.encode_query()

    case Polite.get("#{@base}/app.bsky.actor.getProfiles?#{query}", polite_opts(opts)) do
      {:ok, %{body: %{"profiles" => profiles}}} when is_list(profiles) ->
        {:ok,
         Enum.map(profiles, fn p ->
           %{
             did: p["did"],
             handle: p["handle"],
             display_name: p["displayName"],
             created_at: p["createdAt"]
           }
         end)}

      {:ok, _response} ->
        {:error, :bad_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Extracts link URLs from a post record (link facets and external embeds)."
  @spec links(map()) :: [String.t()]
  def links(record) when is_map(record) do
    facet_links =
      for facet <- List.wrap(record["facets"]),
          feature <- List.wrap(facet["features"]),
          feature["$type"] == "app.bsky.richtext.facet#link",
          is_binary(feature["uri"]),
          do: feature["uri"]

    embed_links =
      [get_in(record, ["embed", "external", "uri"]), get_in(record, ["embed", "media", "external", "uri"])]
      |> Enum.filter(&is_binary/1)

    Enum.uniq(facet_links ++ embed_links)
  end

  defp post(%{"post" => %{"uri" => uri, "author" => author, "record" => record}})
       when is_map(record) do
    [
      %{
        id: uri |> String.split("/") |> List.last(),
        handle: author["handle"],
        text: record["text"] || "",
        urls: links(record),
        published_at: record["createdAt"]
      }
    ]
  end

  defp post(_item), do: []

  # Handles are stored as shown ("@alice.bsky.social"); the API wants them bare.
  defp actor(handle), do: String.trim_leading(handle, "@")

  defp polite_opts(opts), do: Keyword.take(opts, [:plug, :sleep, :min_interval_ms, :robots, :max_retries])
end
