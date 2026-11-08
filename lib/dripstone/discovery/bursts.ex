defmodule Dripstone.Discovery.Bursts do
  @moduledoc """
  Burst prescreening for live discovery: a link posted by at least `threshold`
  distinct accounts within `window_ms` becomes a **candidate group**. Pure: the
  state is a plain struct the stream consumer keeps and threads through
  `observe/4`.

    * Links are normalised (`normalize/1`): lowercase host, no `utm_*`, `fbclid`
      or `ref` parameters, no fragment.
    * Links on `common_domains` are ignored. These are domains everyone posts, so
      sharing them says nothing.
    * The same account repeating a link counts once.
    * After a link produces a candidate, it is in cooldown for `cooldown_ms`.
    * At most `max_tracked` links are tracked; the least recently seen are dropped
      first.
  """

  @defaults [
    threshold: 5,
    window_ms: 10 * 60 * 1000,
    cooldown_ms: 6 * 60 * 60 * 1000,
    max_tracked: 50_000,
    common_domains: ~w(
      bsky.app bsky.social go.bsky.app youtube.com youtu.be x.com twitter.com
      instagram.com tiktok.com google.com wikipedia.org github.com facebook.com
      reddit.com spotify.com open.spotify.com twitch.tv linkedin.com threads.net
      apple.com amazon.com tenor.com giphy.com imgur.com
    )
  ]

  defstruct seen: %{}, cooldown: %{}, config: @defaults

  @type candidate :: %{
          url: String.t(),
          domain: String.t(),
          dids: [String.t()],
          first_at: integer(),
          last_at: integer()
        }

  @doc "A new detector, with `opts` over the defaults (and app config)."
  @spec new(keyword()) :: %__MODULE__{}
  def new(opts \\ []) do
    config =
      @defaults
      |> Keyword.merge(Application.get_env(:dripstone, __MODULE__, []))
      |> Keyword.merge(opts)

    %__MODULE__{config: config}
  end

  @doc """
  Records that `did` posted `url` at `at_ms` (milliseconds). Returns the new state
  and either `nil` or the candidate group the post completed.
  """
  @spec observe(%__MODULE__{}, String.t(), String.t(), integer()) ::
          {%__MODULE__{}, candidate() | nil}
  def observe(%__MODULE__{config: c} = state, did, url, at_ms) do
    with {:ok, link, domain} <- normalize(url),
         false <- common?(domain, c[:common_domains]),
         false <- cooling?(state, link, at_ms) do
      track(state, link, domain, did, at_ms)
    else
      _ -> {state, nil}
    end
  end

  @doc "Normalises a link URL; `{:ok, link, domain}` or `:error` for non-web links."
  @spec normalize(String.t()) :: {:ok, String.t(), String.t()} | :error
  def normalize(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        host = host |> String.downcase() |> String.trim_leading("www.")

        query =
          case uri.query do
            nil ->
              nil

            q ->
              q
              |> URI.decode_query()
              |> Enum.reject(fn {k, _} -> String.starts_with?(k, "utm_") or k in ["fbclid", "ref"] end)
              |> case do
                [] -> nil
                kept -> kept |> Enum.sort() |> URI.encode_query()
              end
          end

        link =
          URI.to_string(%URI{scheme: "https", host: host, path: uri.path || "/", query: query})

        {:ok, link, host}

      _ ->
        :error
    end
  end

  def normalize(_url), do: :error

  defp common?(domain, common) do
    Enum.any?(common, fn d -> domain == d or String.ends_with?(domain, "." <> d) end)
  end

  defp cooling?(state, link, now) do
    case state.cooldown do
      %{^link => until} -> now < until
      _ -> false
    end
  end

  defp track(%{config: c} = state, link, domain, did, now) do
    window_start = now - c[:window_ms]

    entry =
      case state.seen do
        %{^link => entry} -> entry
        _ -> %{domain: domain, posts: %{}}
      end

    # Distinct accounts within the window; a repeat by the same account counts once.
    posts =
      entry.posts
      |> Enum.reject(fn {_did, at} -> at < window_start end)
      |> Map.new()
      |> Map.put_new(did, now)

    entry = %{entry | posts: posts}

    if map_size(posts) >= c[:threshold] do
      times = Map.values(posts)

      candidate = %{
        url: link,
        domain: domain,
        dids: posts |> Map.keys() |> Enum.sort(),
        first_at: Enum.min(times),
        last_at: Enum.max(times)
      }

      state = %{
        state
        | seen: Map.delete(state.seen, link),
          cooldown: Map.put(state.cooldown, link, now + c[:cooldown_ms])
      }

      {prune(state, now), candidate}
    else
      {prune(%{state | seen: Map.put(state.seen, link, entry)}, now), nil}
    end
  end

  # Drops expired cooldowns, and the least recently seen links over the bound.
  defp prune(%{config: c} = state, now) do
    cooldown = state.cooldown |> Enum.reject(fn {_l, until} -> until <= now end) |> Map.new()

    seen =
      if map_size(state.seen) > c[:max_tracked] do
        state.seen
        |> Enum.sort_by(fn {_l, e} -> e.posts |> Map.values() |> Enum.max(fn -> 0 end) end, :desc)
        |> Enum.take(c[:max_tracked])
        |> Map.new()
      else
        state.seen
      end

    %{state | seen: seen, cooldown: cooldown}
  end
end
