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

  @table __MODULE__
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

  defp table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

      tid ->
        tid
    end
  rescue
    ArgumentError -> :ets.whereis(@table)
  end

  # Minimum gap between requests to the same host.
  defp gate(host, interval_ms, sleep) do
    now = System.monotonic_time(:millisecond)

    wait =
      case :ets.lookup(table(), {:last, host}) do
        [{_, last}] -> max(0, interval_ms - (now - last))
        [] -> 0
      end

    if wait > 0, do: sleep.(wait)
    :ets.insert(table(), {{:last, host}, System.monotonic_time(:millisecond)})
    :ok
  end

  # Cached robots.txt check; fetch failures fail open.
  defp robots_allowed?(uri, opts) when is_list(opts) do
    if Keyword.get(opts, :robots, true), do: check_robots(uri, opts), else: true
  end

  defp check_robots(uri, opts) do
    case :ets.lookup(table(), {:robots, uri.host}) do
      [{_, rules}] -> allowed?(uri.path || "/", rules)
      [] -> fetch_robots(uri, opts)
    end
  end

  defp fetch_robots(uri, opts) do
    robots_url = "#{uri.scheme}://#{uri.host}/robots.txt"

    rules =
      case Req.get(robots_url, req_opts(opts)) do
        {:ok, %{status: 200, body: body}} when is_binary(body) -> parse_robots(body)
        _ -> []
      end

    :ets.insert(table(), {{:robots, uri.host}, rules})
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

  defp retry_after_ms(resp) do
    case Req.Response.get_header(resp, "retry-after") do
      [secs | _] ->
        case Integer.parse(String.trim(secs)) do
          {n, ""} when n >= 0 -> n * 1_000
          _ -> 0
        end

      [] ->
        1_000
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
