defmodule Dripstone.Adapters.Mastodon do
  @moduledoc """
  Real Mastodon fetcher behind the shared `fetch_posts(handle, opts)` behaviour.

  Handles look like `user@instance` (`@` prefix optional). It reads the account's
  recent posts from **its home instance's** public API, with no authentication:
  `/api/v1/accounts/lookup`, then `/api/v1/accounts/:id/statuses` (no replies, no
  boosts). It goes through `Dripstone.Adapters.Polite` (per-host spacing,
  robots.txt, 429 back-off).

  Posts come back canonical, `%{id, handle, text, urls, published_at}`, with the
  HTML content flattened to text. `links/1` returns a status's outbound links,
  leaving out mentions and hashtags; the discovery poller uses it too.
  """

  @behaviour Dripstone.Adapters

  alias Dripstone.Adapters.Polite

  @default_limit 30

  @impl true
  def fetch_posts(handle, opts \\ []) when is_binary(handle) do
    with {:ok, user, instance} <- split(handle),
         {:ok, account} <- lookup(user, instance, opts),
         {:ok, statuses} <- statuses(instance, account["id"], opts) do
      acct = "#{user}@#{instance}"
      {:ok, Enum.map(statuses, &post(&1, acct))}
    end
  end

  @doc "The account's public profile: `%{acct, display_name, created_at, url}`."
  @spec profile(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def profile(handle, opts \\ []) do
    with {:ok, user, instance} <- split(handle),
         {:ok, a} <- lookup(user, instance, opts) do
      {:ok,
       %{
         acct: "#{user}@#{instance}",
         display_name: a["display_name"],
         created_at: a["created_at"],
         url: a["url"]
       }}
    end
  end

  @doc """
  Splits `@user@instance` / `user@instance` into `{:ok, user, instance}`. A bare
  `user` (a local account in a timeline) needs `default_instance`.
  """
  @spec split(String.t(), String.t() | nil) :: {:ok, String.t(), String.t()} | {:error, term()}
  def split(handle, default_instance \\ nil) do
    case handle |> String.trim_leading("@") |> String.split("@", parts: 2) do
      [user, instance] when user != "" and instance != "" ->
        {:ok, user, String.downcase(instance)}

      [user] when user != "" and is_binary(default_instance) ->
        {:ok, user, default_instance}

      _ ->
        {:error, {:invalid_handle, handle}}
    end
  end

  @doc "Outbound links of a status: content links (not mentions or hashtags) and its card."
  @spec links(map()) :: [String.t()]
  def links(status) when is_map(status) do
    content_links =
      ~r/<a\s+([^>]*)>/i
      |> Regex.scan(status["content"] || "", capture: :all_but_first)
      |> Enum.flat_map(fn [attrs] ->
        href = Regex.run(~r/href="([^"]+)"/i, attrs, capture: :all_but_first)
        mention_or_tag? = attrs =~ ~r/class="[^"]*(mention|hashtag)/i

        case href do
          [url] when not mention_or_tag? -> [unescape(url)]
          _ -> []
        end
      end)

    card = get_in(status, ["card", "url"])
    Enum.uniq(content_links ++ if(is_binary(card), do: [card], else: []))
  end

  @doc "Flattens a status's HTML content to plain text."
  @spec text(String.t() | nil) :: String.t()
  def text(nil), do: ""

  def text(html) do
    html
    |> String.replace(~r/<br\s*\/?>|<\/p>/i, "\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> unescape()
    |> String.trim()
  end

  defp lookup(user, instance, opts) do
    url = "https://#{instance}/api/v1/accounts/lookup?" <> URI.encode_query(%{"acct" => user})

    case Polite.get(url, polite_opts(opts)) do
      {:ok, %{body: %{"id" => _} = account}} -> {:ok, account}
      {:ok, _} -> {:error, :bad_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp statuses(instance, id, opts) do
    query =
      URI.encode_query(%{
        "limit" => Keyword.get(opts, :limit, @default_limit),
        "exclude_replies" => "true",
        "exclude_reblogs" => "true"
      })

    case Polite.get(
           "https://#{instance}/api/v1/accounts/#{id}/statuses?#{query}",
           polite_opts(opts)
         ) do
      {:ok, %{body: statuses}} when is_list(statuses) -> {:ok, statuses}
      {:ok, _} -> {:error, :bad_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp post(status, acct) do
    %{
      id: to_string(status["id"]),
      handle: acct,
      text: text(status["content"]),
      urls: links(status),
      published_at: status["created_at"]
    }
  end

  defp unescape(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
  end

  defp polite_opts(opts),
    do: Keyword.take(opts, [:plug, :sleep, :min_interval_ms, :robots, :max_retries])
end
