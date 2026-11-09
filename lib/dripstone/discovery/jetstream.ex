defmodule Dripstone.Discovery.Jetstream do
  @moduledoc """
  Live discovery's stream consumer (live-discovery "Live stream ingestion"):
  connects to Bluesky's public Jetstream (no authentication) for
  `app.bsky.feed.post` events and runs every post that carries a link through
  `Dripstone.Discovery.Bursts`. Each candidate group it completes is queued as a
  `Dripstone.Workers.DiscoverWorker` job.

    * Enabled by `config :dripstone, Dripstone.Discovery, enabled: true` (prod;
      `DRIPSTONE_DISCOVERY=1` in dev; never in test). See `enabled?/0`.
    * It reconnects with back-off, resuming a few seconds before the last event
      seen (Jetstream's `cursor`), so a short drop doesn't lose a burst.
    * **Feed health without per-post writes.** It counts in memory (last item, a
      24-hour item window, connection state, last error) and writes the Bluesky
      `FeedHealth` to Live once every `flush_ms` (60 s), in one write. A
      per-post write would rewrite the database hundreds of times a second.

  `handle_event/3` and `health/2` are pure, so they're tested from recorded
  frames without the network.
  """

  use GenServer

  require Logger

  alias Dripstone.Adapters.Bluesky
  alias Dripstone.Discovery.Bursts
  alias Dripstone.Tracker.{FeedHealth, Store}
  alias Dripstone.Workers.DiscoverWorker

  @default_url "wss://jetstream2.us-east.bsky.network/subscribe?wantedCollections=app.bsky.feed.post"
  @flush_ms 60_000
  @watchdog_ms 30_000
  @idle_ms 90_000
  @max_backoff_ms 60_000
  @cursor_rewind_us 5_000_000
  @day_s 24 * 60 * 60
  @socket_tags [:ssl, :ssl_closed, :ssl_error, :tcp, :tcp_closed, :tcp_error]

  ## Config

  @doc "Whether live discovery is switched on."
  @spec enabled?() :: boolean()
  def enabled?, do: config(:enabled, false) == true

  defp config(key, default),
    do: :dripstone |> Application.get_env(Dripstone.Discovery, []) |> Keyword.get(key, default)

  ## Pure event handling

  @doc """
  Handles one decoded Jetstream event. Returns the new state and the candidate
  groups it completed (usually none). Only `create` commits of posts with links
  count; everything else just advances the cursor.
  """
  @spec handle_event(map(), map(), DateTime.t()) :: {map(), [Bursts.candidate()]}
  def handle_event(state, %{"kind" => "commit", "did" => did, "time_us" => time_us} = event, now) do
    state = %{state | cursor_us: time_us}

    case event["commit"] do
      %{"operation" => "create", "collection" => "app.bsky.feed.post", "record" => record}
      when is_map(record) ->
        state = count_item(state, now)

        record
        |> Bluesky.links()
        |> Enum.reduce({state, []}, fn url, {state, found} ->
          {bursts, candidate} = Bursts.observe(state.bursts, did, url, div(time_us, 1000))
          state = %{state | bursts: bursts}
          if candidate, do: {state, found ++ [candidate]}, else: {state, found}
        end)

      _ ->
        {state, []}
    end
  end

  def handle_event(state, %{"time_us" => time_us}, _now), do: {%{state | cursor_us: time_us}, []}
  def handle_event(state, _event, _now), do: {state, []}

  @doc "A fresh consumer state (exposed for tests)."
  @spec new_state(keyword()) :: map()
  def new_state(opts \\ []) do
    %{
      bursts: Bursts.new(Keyword.get(opts, :bursts, [])),
      cursor_us: nil,
      connected: false,
      last_item_at: nil,
      window_started_at: nil,
      items_24h: 0,
      last_error: nil,
      last_error_at: nil
    }
  end

  defp count_item(state, now) do
    expired = state.window_started_at && DateTime.diff(now, state.window_started_at) >= @day_s

    if is_nil(state.window_started_at) or expired,
      do: %{state | last_item_at: now, window_started_at: now, items_24h: 1},
      else: %{state | last_item_at: now, items_24h: state.items_24h + 1}
  end

  @doc """
  The Bluesky `FeedHealth` for the current counters. Down while disconnected;
  otherwise healthy (Queries derives Degraded from the last-item time).
  """
  @spec health(map(), DateTime.t()) :: FeedHealth.t()
  def health(state, _now) do
    %FeedHealth{
      feed_id: "bluesky",
      status: if(state.connected, do: :healthy, else: :down),
      last_item_at: state.last_item_at && DateTime.truncate(state.last_item_at, :second),
      items_24h: state.items_24h,
      window_started_at:
        state.window_started_at && DateTime.truncate(state.window_started_at, :second),
      last_error: state.last_error,
      last_error_at: state.last_error_at && DateTime.truncate(state.last_error_at, :second)
    }
  end

  @doc "Writes the Bluesky feed health into Live, in one write."
  @spec flush_health(map()) :: :ok
  def flush_health(state) do
    health = health(state, DateTime.utc_now())

    {:ok, :ok} =
      Store.write(fn ->
        {:ok, tracker} = Store.load()
        others = Enum.reject(tracker.feed_health, &(&1.feed_id == "bluesky"))
        :ok = Store.save(%{tracker | feed_health: [health | others]})
        {:ok, :ok}
      end)

    :ok
  end

  ## Process

  @doc false
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    state =
      opts
      |> new_state()
      |> Map.merge(%{
        url: Keyword.get(opts, :url, config(:url, @default_url)),
        enqueue: Keyword.get(opts, :enqueue, &Oban.insert/1),
        conn: nil,
        ref: nil,
        websocket: nil,
        backoff_ms: 1_000,
        idle_ms: Keyword.get(opts, :idle_ms, @idle_ms),
        last_data_ms: nil
      })

    send(self(), :connect)
    Process.send_after(self(), :flush, @flush_ms)
    Process.send_after(self(), :watchdog, @watchdog_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case connect(state) do
      {:ok, state} ->
        Logger.info("Jetstream connected")
        {:noreply, %{state | backoff_ms: 1_000, last_data_ms: now_ms()}}

      {:error, reason, state} ->
        {:noreply, disconnected(state, reason)}
    end
  end

  def handle_info(:flush, state) do
    try do
      flush_health(state)
    rescue
      e -> Logger.warning("Jetstream health flush failed: #{Exception.message(e)}")
    end

    Process.send_after(self(), :flush, @flush_ms)
    {:noreply, state}
  end

  # A connection can go quiet without ever closing (a half-open TCP connection,
  # or a stalled server). Jetstream sends hundreds of events a second, so a long
  # silence means the stream is dead: drop it and reconnect from the cursor.
  def handle_info(:watchdog, state) do
    state =
      if idle?(state, now_ms()),
        do: disconnected(state, {:idle_timeout, state.idle_ms}),
        else: state

    Process.send_after(self(), :watchdog, @watchdog_ms)
    {:noreply, state}
  end

  def handle_info(message, %{conn: conn} = state) when not is_nil(conn) do
    case Mint.WebSocket.stream(conn, message) do
      {:ok, conn, responses} ->
        state = %{state | conn: conn, last_data_ms: now_ms()}
        {:noreply, Enum.reduce(responses, state, &handle_response/2)}

      {:error, conn, reason, _responses} ->
        {:noreply, disconnected(%{state | conn: conn}, reason)}

      :unknown ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @doc """
  Whether a connected stream has gone quiet for longer than `idle_ms` (default
  90 s) as of `now_ms` (monotonic milliseconds). Never true while disconnected,
  since reconnecting is already under way then.
  """
  @spec idle?(map(), integer()) :: boolean()
  def idle?(%{conn: nil}, _now_ms), do: false
  def idle?(%{last_data_ms: nil}, _now_ms), do: false

  def idle?(%{last_data_ms: last, idle_ms: idle_ms}, now_ms), do: now_ms - last > idle_ms

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp handle_response({:data, ref, data}, %{ref: ref, websocket: ws} = state)
       when not is_nil(ws) do
    case Mint.WebSocket.decode(ws, data) do
      {:ok, ws, frames} -> Enum.reduce(frames, %{state | websocket: ws}, &handle_frame/2)
      {:error, ws, reason} -> disconnected(%{state | websocket: ws}, reason)
    end
  end

  defp handle_response(_response, state), do: state

  defp handle_frame({:text, json}, state) do
    case Jason.decode(json) do
      {:ok, event} ->
        {state, candidates} = handle_event(state, event, DateTime.utc_now())
        Enum.each(candidates, &enqueue(state, &1))
        state

      _ ->
        state
    end
  end

  defp handle_frame({:ping, data}, state), do: send_frame(state, {:pong, data})
  defp handle_frame({:close, _code, reason}, state), do: disconnected(state, {:closed, reason})
  defp handle_frame(_frame, state), do: state

  defp enqueue(state, candidate) do
    args = %{"url" => candidate.url, "domain" => candidate.domain, "dids" => candidate.dids}

    case state.enqueue.(DiscoverWorker.new(args)) do
      {:ok, _job} ->
        Logger.info(
          "Discovery candidate: #{length(candidate.dids)} accounts posted #{candidate.url}"
        )

      {:error, reason} ->
        Logger.warning("Discovery could not queue a candidate: #{inspect(reason)}")
    end
  end

  defp send_frame(%{conn: conn, ref: ref, websocket: ws} = state, frame) do
    with {:ok, ws, data} <- Mint.WebSocket.encode(ws, frame),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(conn, ref, data) do
      %{state | conn: conn, websocket: ws}
    else
      {:error, _ws_or_conn, reason} -> disconnected(state, reason)
    end
  end

  # Opens the connection and completes the WebSocket upgrade (blocking, bounded).
  defp connect(state) do
    uri = URI.parse(resume_url(state))
    path = uri.path <> if(uri.query, do: "?" <> uri.query, else: "")

    with {:ok, conn} <- Mint.HTTP.connect(:https, uri.host, uri.port || 443, protocols: [:http1]),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(:wss, conn, path, []),
         {:ok, conn, status, headers} <- await_upgrade(conn, ref),
         {:ok, conn, websocket} <- Mint.WebSocket.new(conn, ref, status, headers) do
      {:ok, %{state | conn: conn, ref: ref, websocket: websocket, connected: true}}
    else
      {:error, reason} -> {:error, reason, state}
      {:error, conn, reason} -> {:error, reason, %{state | conn: conn}}
    end
  end

  defp await_upgrade(conn, ref, acc \\ %{}) do
    # Only socket messages: anything else (e.g. the :flush timer) stays queued.
    receive do
      message when is_tuple(message) and elem(message, 0) in @socket_tags ->
        case Mint.WebSocket.stream(conn, message) do
          {:ok, conn, responses} ->
            acc =
              Enum.reduce(responses, acc, fn
                {:status, ^ref, status}, acc -> Map.put(acc, :status, status)
                {:headers, ^ref, headers}, acc -> Map.put(acc, :headers, headers)
                {:done, ^ref}, acc -> Map.put(acc, :done, true)
                _, acc -> acc
              end)

            if acc[:done],
              do: {:ok, conn, acc.status, acc.headers},
              else: await_upgrade(conn, ref, acc)

          {:error, conn, reason, _} ->
            {:error, conn, reason}

          :unknown ->
            await_upgrade(conn, ref, acc)
        end
    after
      15_000 -> {:error, conn, :upgrade_timeout}
    end
  end

  defp resume_url(%{url: url, cursor_us: nil}), do: url

  defp resume_url(%{url: url, cursor_us: cursor}) do
    sep = if String.contains?(url, "?"), do: "&", else: "?"
    url <> sep <> "cursor=" <> Integer.to_string(cursor - @cursor_rewind_us)
  end

  defp disconnected(state, reason) do
    if state.conn, do: Mint.HTTP.close(state.conn)

    Logger.warning(
      "Jetstream disconnected: #{inspect(reason)}; retrying in #{state.backoff_ms} ms"
    )

    Process.send_after(self(), :connect, state.backoff_ms)

    %{
      state
      | conn: nil,
        ref: nil,
        websocket: nil,
        connected: false,
        last_error: inspect(reason),
        last_error_at: DateTime.utc_now(),
        backoff_ms: min(state.backoff_ms * 2, @max_backoff_ms)
    }
  end
end
