defmodule Dripstone.Discovery.MastodonPoller do
  @moduledoc """
  Live discovery on Mastodon. Every `interval_ms` (30 s) it reads the public
  timelines of a few open instances (`/api/v1/timelines/public`, no authentication,
  through `Dripstone.Adapters.Polite`). These timelines are mostly federated posts
  from across the fediverse. Each post with an outbound link goes through its own
  `Dripstone.Discovery.Bursts` detector, and each candidate group (one link, 5+
  distinct accounts, 10 minutes) is queued as a `DiscoverWorker` job with
  `"platform" => "mastodon"`.

    * Instances come from `config :dripstone, Dripstone.Discovery,
      mastodon_instances: [...]`. Only instances that allow unauthenticated public
      timelines work; others answer 401/422 and are reported in feed health.
    * Each instance keeps a `since_id`, so a post is seen once.
    * Boosts are skipped, since a boost isn't the account posting the link.
      Accounts are keyed `user@instance`; local accounts get their instance added.
    * The Mastodon `FeedHealth` is written to Live once a minute.

  `handle_status/4` is pure and is tested from recorded statuses.
  """

  use GenServer

  require Logger

  alias Dripstone.Adapters.{Mastodon, Polite}
  alias Dripstone.Discovery.{Bursts, Health}
  alias Dripstone.Workers.DiscoverWorker

  @interval_ms 30_000
  @flush_ms 60_000

  ## Pure

  @doc "A fresh poller state (exposed for tests)."
  @spec new_state(keyword()) :: map()
  def new_state(opts \\ []) do
    %{
      bursts: Bursts.new(Keyword.get(opts, :bursts, [])),
      since: %{},
      health: Health.new()
    }
  end

  @doc """
  Handles one status from `instance`'s public timeline. Returns the new state and
  the candidate groups it completed.
  """
  @spec handle_status(map(), map(), String.t(), DateTime.t()) :: {map(), [Bursts.candidate()]}
  def handle_status(state, %{"reblog" => reblog}, _instance, _now) when is_map(reblog),
    do: {state, []}

  def handle_status(
        state,
        %{"account" => %{"acct" => acct}, "created_at" => created} = status,
        instance,
        now
      ) do
    state = %{state | health: Health.count_item(state.health, now)}

    with {:ok, user, home} <- Mastodon.split(acct, instance),
         {:ok, at, _} <- DateTime.from_iso8601(created) do
      key = "#{user}@#{home}"
      at_ms = DateTime.to_unix(at, :millisecond)

      status
      |> Mastodon.links()
      |> Enum.reduce({state, []}, fn url, {state, found} ->
        {bursts, candidate} = Bursts.observe(state.bursts, key, url, at_ms)
        state = %{state | bursts: bursts}
        if candidate, do: {state, found ++ [candidate]}, else: {state, found}
      end)
    else
      _ -> {state, []}
    end
  end

  def handle_status(state, _status, _instance, _now), do: {state, []}

  ## Process

  @doc false
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    config = Application.get_env(:dripstone, Dripstone.Discovery, [])

    state =
      opts
      |> new_state()
      |> Map.merge(%{
        instances: Keyword.get(opts, :instances, Keyword.get(config, :mastodon_instances, [])),
        interval_ms: Keyword.get(opts, :interval_ms, @interval_ms),
        enqueue: Keyword.get(opts, :enqueue, &Oban.insert/1),
        http_opts: Keyword.get(opts, :http_opts, [])
      })

    send(self(), :poll)
    Process.send_after(self(), :flush, @flush_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = Enum.reduce(state.instances, state, &poll_instance/2)
    Process.send_after(self(), :poll, state.interval_ms)
    {:noreply, state}
  end

  def handle_info(:flush, state) do
    try do
      state.health |> Health.to_feed_health("mastodon") |> Health.write()
    rescue
      e -> Logger.warning("Mastodon health flush failed: #{Exception.message(e)}")
    end

    Process.send_after(self(), :flush, @flush_ms)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp poll_instance(instance, state) do
    query =
      %{"limit" => 40}
      |> then(fn q -> if id = state.since[instance], do: Map.put(q, "since_id", id), else: q end)
      |> URI.encode_query()

    case Polite.get("https://#{instance}/api/v1/timelines/public?#{query}", state.http_opts) do
      {:ok, %{body: statuses}} when is_list(statuses) ->
        now = DateTime.utc_now()

        # Oldest first, so bursts see posts in order.
        {state, candidates} =
          statuses
          |> Enum.reverse()
          |> Enum.reduce({state, []}, fn status, {state, found} ->
            {state, c} = handle_status(state, status, instance, now)
            {state, found ++ c}
          end)

        Enum.each(candidates, &enqueue(state, &1))
        newest = statuses |> List.first() |> then(&(&1 && &1["id"]))
        since = if newest, do: Map.put(state.since, instance, newest), else: state.since
        %{state | since: since, health: %{state.health | connected: true}}

      other ->
        reason = if match?({:error, _}, other), do: elem(other, 1), else: :bad_response
        Logger.warning("Mastodon timeline #{instance} failed: #{inspect(reason)}")

        %{
          state
          | health: %{
              state.health
              | last_error: "#{instance}: #{inspect(reason)}",
                last_error_at: DateTime.utc_now(),
                connected: state.health.connected and length(state.instances) > 1
            }
        }
    end
  end

  defp enqueue(state, candidate) do
    args = %{
      "platform" => "mastodon",
      "url" => candidate.url,
      "domain" => candidate.domain,
      "dids" => candidate.dids
    }

    case state.enqueue.(DiscoverWorker.new(args)) do
      {:ok, _job} ->
        Logger.info(
          "Discovery candidate (Mastodon): #{length(candidate.dids)} accounts posted #{candidate.url}"
        )

      {:error, reason} ->
        Logger.warning("Discovery could not queue a Mastodon candidate: #{inspect(reason)}")
    end
  end
end
