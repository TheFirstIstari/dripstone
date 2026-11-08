defmodule Dripstone.Adapters.Polite do
  @moduledoc """
  Shared HTTP politeness layer for source fetchers.

  Every fetcher goes through `get/2`, which applies — in order — a
  per-host rate gate, a `robots.txt` check, and 429 backoff honoring
  `Retry-After`. Returns `{:ok, resp}` on 2xx, `{:error, reason}`
  otherwise; fetchers map that into their `{:ok, posts} | {:error,
  reason}` contract. No fetcher does its own HTTP politeness.

  Tunables (`opts`, falling back to app env, then defaults):

    * `:min_interval_ms` — minimum gap between requests to one host (default 1_000)
    * `:max_retries` — extra attempts after a 429 (default 3)
    * `:user_agent` — sent on every request (default `"DripstoneBot/0.1 (+research)"`)
    * `:robots` — set `false` to skip the robots check (default `true`)
    * `:retry_after_cap_ms` — upper bound on a single 429 sleep (default 30_000)
    * `:sleep` — sleep fun, injectable for tests (default `&:timer.sleep/1`)
    * `:plug` — test-only `Req.Test` stub, never forwarded from user input
  """

  @default_interval_ms 1_000
  @default_retries 3
  @default_cap_ms 30_000
  @default_ua "DripstoneBot/0.1 (+research)"

  @doc """
  Polite GET. Returns `{:ok, resp}` on 2xx, `{:error, reason}` otherwise.
  """
  @spec get(String.t(), keyword()) ::
          {:ok, Req.Response.t()}
          | {:error,
             :disallowed_by_robots
             | {:rate_limited, non_neg_integer()}
             | {:http_error, non_neg_integer()}
             | {:transport, term()}
             | {:invalid_args, String.t()}}
  def get(url, opts \\ []) when is_list(opts) do
    with {:ok, uri} <- parse_url(url) do
      host = uri.host
      sleep = Keyword.get(opts, :sleep, &:timer.sleep/1)

      gate(host, interval_ms(opts), sleep)

      case robots_allowed?(uri, opts) do
        true -> request(url, uri, host, opts, sleep, 0)
        false -> {:error, :disallowed_by_robots}
      end
    end
  end

  defp parse_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: s, host: host}
      when s in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, URI.parse(url)}

      _ ->
        {:error, {:invalid_args, "url must be an absolute http(s) URL"}}
    end
  end

  defp parse_url(_), do: {:error, {:invalid_args, "url must be an absolute http(s) URL"}}

  defp interval_ms(opts) do
    Keyword.get_lazy(opts, :min_interval_ms, fn ->
      Application.get_env(:dripstone, __MODULE__, [])
      |> Keyword.get(:min_interval_ms, @default_interval_ms)
    end)
  end

  # Minimum gap between requests to the same host. The slot is booked
  # atomically by the long-lived Polite.Gate, so concurrent callers (Oban jobs)
  # are spaced too and the bookings outlive each caller.
  defp gate(host, interval_ms, sleep) do
    case Dripstone.Adapters.Polite.Gate.reserve(host, interval_ms) do
      0 -> :ok
      wait -> sleep.(wait)
    end

    :ok
  end

  # Cached robots.txt check; fetch failures fail open.
  defp robots_allowed?(uri, opts) when is_list(opts) do
    if Keyword.get(opts, :robots, true), do: check_robots(uri, opts), else: true
  end

  defp check_robots(uri, opts) do
    case Dripstone.Adapters.Polite.Gate.robots(uri.host) do
      {:ok, rules} -> allowed?(uri.path || "/", rules)
      :miss -> fetch_robots(uri, opts)
    end
  end

  defp fetch_robots(uri, opts) do
    robots_url = "#{uri.scheme}://#{uri.host}/robots.txt"

    rules =
      case Req.get(robots_url, req_opts(opts)) do
        {:ok, %{status: 200, body: body}} when is_binary(body) -> parse_robots(body)
        _ -> []
      end

    :ok = Dripstone.Adapters.Polite.Gate.put_robots(uri.host, rules)
    allowed?(uri.path || "/", rules)
  end

  # Minimal parser: Disallow lines applying to `User-agent: *` (or all
  # agents when no agent section matched — conservative enough for a guest).
  defp parse_robots(body) do
    {rules, _} =
      body
      |> String.split(~r/\r?\n/)
      |> Enum.reduce({[], true}, fn line, {rules, relevant} ->
        line = line |> String.split("#", parts: 2) |> hd() |> String.trim()

        cond do
          String.match?(line, ~r/(?i)^user-agent\s*:/) ->
            agent = line |> String.split(":", parts: 2) |> List.last() |> String.trim()
            {rules, agent == "*"}

          relevant and String.match?(line, ~r/(?i)^disallow\s*:/) ->
            path = line |> String.split(":", parts: 2) |> List.last() |> String.trim()
            if path == "", do: {rules, relevant}, else: {[path | rules], relevant}

          true ->
            {rules, relevant}
        end
      end)

    rules
  end

  defp allowed?(_path, []), do: true
  defp allowed?(path, rules), do: not Enum.any?(rules, &String.starts_with?(path, &1))

  defp request(url, uri, host, opts, sleep, attempt) do
    max = Keyword.get(opts, :max_retries, @default_retries)
    cap = Keyword.get(opts, :retry_after_cap_ms, @default_cap_ms)

    case Req.get(url, req_opts(opts)) do
      {:ok, %{status: 429} = resp} when attempt < max ->
        sleep.(min(retry_after_ms(resp), cap))
        gate(host, interval_ms(opts), sleep)
        request(url, uri, host, opts, sleep, attempt + 1)

      {:ok, %{status: 429}} ->
        {:error, {:rate_limited, max + 1}}

      {:ok, %{status: status} = resp} when status in 200..299 ->
        {:ok, resp}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:transport, reason}}
    end
  end

  # Retry-After is either delay-seconds or an HTTP date (RFC 9110).
  defp retry_after_ms(resp) do
    case Req.Response.get_header(resp, "retry-after") do
      [value | _] ->
        value = String.trim(value)

        case Integer.parse(value) do
          {n, ""} when n >= 0 -> n * 1_000
          _ -> http_date_ms(value)
        end

      [] ->
        1_000
    end
  end

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  # IMF-fixdate, e.g. "Wed, 21 Oct 2015 07:28:00 GMT" (the form RFC 9110 requires).
  defp http_date_ms(value) do
    with [_, d, mon, y, h, mi, sec] <-
           Regex.run(~r/^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$/, value),
         month when is_integer(month) <- Enum.find_index(@months, &(&1 == mon)),
         {:ok, at} <-
           NaiveDateTime.new(
             String.to_integer(y),
             month + 1,
             String.to_integer(d),
             String.to_integer(h),
             String.to_integer(mi),
             String.to_integer(sec)
           ) do
      at |> DateTime.from_naive!("Etc/UTC") |> DateTime.diff(DateTime.utc_now(), :millisecond) |> max(0)
    else
      _ -> 1_000
    end
  end

  defp req_opts(opts) do
    ua =
      Keyword.get_lazy(opts, :user_agent, fn ->
        Application.get_env(:dripstone, __MODULE__, [])
        |> Keyword.get(:user_agent, @default_ua)
      end)

    [headers: [{"user-agent", ua}], retry: false]
    |> Keyword.merge(Keyword.take(opts, [:plug]))
  end
end
