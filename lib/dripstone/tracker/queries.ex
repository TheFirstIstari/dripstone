defmodule Dripstone.Tracker.Queries do
  @moduledoc """
  Read-only queries over `Dripstone.Tracker.State`, shaped for the screens.

  Filter params are maps with atom keys whose values are already validated by the
  caller (LiveViews parse URL params against allow-lists). Unknown keys are ignored.
  Retired (merged) networks never appear in lists.
  """

  alias Dripstone.Alerts
  alias Dripstone.Feeds
  alias Dripstone.Tracker.{Alert, FeedHealth, Link, Network, State}

  @per_page 50
  @strength_rank %{weak: 1, moderate: 2, strong: 3}

  ## Risk

  @doc "Maps a 0–100 risk score to `:low` (0–39), `:medium` (40–69) or `:high` (70–100)."
  @spec risk_level(integer()) :: :low | :medium | :high
  def risk_level(score) when score >= 70, do: :high
  def risk_level(score) when score >= 40, do: :medium
  def risk_level(_score), do: :low

  ## Overview

  def overview(%State{} = state, now) do
    alerts = Map.values(state.alerts)
    open = Enum.filter(alerts, &(&1.status == :open))
    today = DateTime.to_date(now)
    days = Enum.map(29..0//-1, &Date.add(today, -&1))
    per_day = Enum.frequencies_by(alerts, &DateTime.to_date(&1.raised_at))
    trend = Enum.map(days, &%{date: &1, count: Map.get(per_day, &1, 0)})

    %{
      open_alerts: length(open),
      open_high_alerts: Enum.count(open, &(&1.severity == :high)),
      suspected_networks: state |> active_networks() |> Enum.count(&(&1.status == :suspected)),
      tracked_accounts: map_size(state.accounts),
      trend: trend,
      trend_total: Enum.sum(Enum.map(trend, & &1.count)),
      newest_open_alerts:
        open |> newest_first() |> Enum.take(5) |> Enum.map(&alert_entry(state, &1)),
      recent_networks: state |> list_networks(%{}) |> Enum.take(5),
      feeds: state |> feed_health(now) |> Enum.sort_by(&(&1.health.status != :healthy), :desc)
    }
  end

  ## Alerts

  @doc """
  Alerts newest first. Filters: `:status` (default `:open`; `:all` for every status),
  `:severity`, `:trigger` (catalog id) and `:platform` (feed id).
  """
  def list_alerts(%State{} = state, params) do
    status = Map.get(params, :status, :open)

    state.alerts
    |> Map.values()
    |> Enum.filter(fn alert ->
      network = state.networks[alert.network_id]

      (status == :all or alert.status == status) and
        matches?(params, :severity, alert.severity) and
        matches?(params, :trigger, alert.trigger_id) and
        (is_nil(params[:platform]) or params[:platform] in network.platforms)
    end)
    |> newest_first()
    |> Enum.map(&alert_entry(state, &1))
  end

  def get_alert(%State{} = state, id) do
    with %Alert{} = alert <- state.alerts[id] do
      network = state.networks[alert.network_id]

      %{
        alert: %{
          alert
          | evidence: Enum.sort_by(alert.evidence, &@strength_rank[&1.strength], :desc)
        },
        network: network,
        trigger_type: Alerts.get_trigger_type(alert.trigger_id),
        decision: alert.decision_id && state.decisions[alert.decision_id],
        previously_dismissed:
          alert.previously_dismissed_alert_id && state.alerts[alert.previously_dismissed_alert_id],
        accounts: evidence_accounts(state, alert.evidence)
      }
    end
  end

  @doc """
  Position of alert `id` within `list_alerts(params)`, with the previous and next ids.
  If the alert is no longer in the list (e.g. just decided), `next` is the alert that
  now holds its old place.
  """
  def alert_neighbors(%State{} = state, id, params) do
    ids = state |> list_alerts(params) |> Enum.map(& &1.alert.id)
    total = length(ids)

    case Enum.find_index(ids, &(&1 == id)) do
      nil ->
        alert = state.alerts[id]
        rest = if alert, do: Enum.drop_while(ids, &newer?(state.alerts[&1], alert)), else: ids
        %{position: nil, total: total, prev: nil, next: List.first(rest)}

      index ->
        %{
          position: index + 1,
          total: total,
          prev: if(index > 0, do: Enum.at(ids, index - 1)),
          next: Enum.at(ids, index + 1)
        }
    end
  end

  defp alert_entry(state, alert), do: %{alert: alert, network: state.networks[alert.network_id]}

  defp newest_first(alerts), do: Enum.sort(alerts, &newer_or_equal?/2)

  defp newer_or_equal?(a, b) do
    case DateTime.compare(a.raised_at, b.raised_at) do
      :gt -> true
      :lt -> false
      :eq -> a.id >= b.id
    end
  end

  defp newer?(a, b), do: newer_or_equal?(a, b) and a.id != b.id

  ## Networks

  @doc """
  Active (non-retired) networks, most recently active first. Filters: `:status`,
  `:platform` (feed id) and `:tag`. Each entry includes its open alert count.
  """
  def list_networks(%State{} = state, params) do
    open_counts =
      state.alerts
      |> Map.values()
      |> Enum.filter(&(&1.status == :open))
      |> Enum.frequencies_by(& &1.network_id)

    state
    |> active_networks()
    |> Enum.filter(fn network ->
      matches?(params, :status, network.status) and
        (is_nil(params[:platform]) or params[:platform] in network.platforms) and
        (is_nil(params[:tag]) or params[:tag] in network.tags)
    end)
    |> Enum.map(fn network ->
      %{
        network: network,
        last_activity_at: network.last_activity_at,
        open_alerts: Map.get(open_counts, network.id, 0)
      }
    end)
    |> Enum.sort_by(&{&1.last_activity_at, &1.network.id}, &later_or_equal?/2)
  end

  @doc "Active networks as `{name, id}` options for filter dropdowns, sorted by name."
  def list_network_options(%State{} = state) do
    state
    |> active_networks()
    |> Enum.map(&{&1.name, &1.id})
    |> Enum.sort()
  end

  def get_network(%State{} = state, id) do
    with %Network{} = network <- state.networks[id] do
      members =
        network.member_ids
        |> Enum.map(&%{account: state.accounts[&1], joined_at: network.joined_at[&1]})
        |> Enum.reject(&is_nil(&1.account))
        |> Enum.sort_by(&{-&1.account.risk_score, &1.account.id})

      %{
        network: network,
        members: members,
        last_activity_at: network.last_activity_at,
        alerts:
          state.alerts |> Map.values() |> Enum.filter(&(&1.network_id == id)) |> newest_first(),
        notes:
          state.notes
          |> Map.values()
          |> Enum.filter(&(&1.network_id == id))
          |> Enum.sort_by(&{&1.at, &1.id}, &later_or_equal?/2),
        history: Enum.filter(state.history, &(&1.network_id == id)),
        related: network.related_ids |> Enum.map(&state.networks[&1]) |> Enum.reject(&is_nil/1),
        retired_into: network.retired_into && state.networks[network.retired_into],
        heatmap: heatmap(state, network)
      }
    end
  end

  @doc "Tags in use on active networks that start with `prefix`, sorted."
  def list_tags(%State{} = state, prefix) do
    prefix = prefix |> to_string() |> Dripstone.Tracker.Curation.normalize_tag()

    state
    |> active_networks()
    |> Enum.flat_map(& &1.tags)
    |> Enum.uniq()
    |> Enum.filter(&String.starts_with?(&1, prefix))
    |> Enum.sort()
  end

  defp active_networks(state),
    do: state.networks |> Map.values() |> Enum.filter(&is_nil(&1.retired_into))

  @doc false
  def heatmap(state, network) do
    {cells, by_hour, weekend_hours} =
      Enum.reduce(network.member_ids, {%{}, %{}, MapSet.new()}, fn id, acc ->
        Enum.reduce(Map.get(state.posts, id, []), acc, fn
          %{posted_at: nil}, acc ->
            acc

          post, {cells, by_hour, weekend_hours} ->
            key = {Date.day_of_week(post.posted_at), post.posted_at.hour}

            {
              Map.update(cells, key, 1, &(&1 + 1)),
              Map.update(by_hour, post.posted_at.hour, 1, &(&1 + 1)),
              if(elem(key, 0) > 5,
                do: MapSet.put(weekend_hours, post.posted_at.hour),
                else: weekend_hours
              )
            }
        end)
      end)

    busiest =
      case Enum.max_by(by_hour, fn {_hour, n} -> n end, fn -> nil end) do
        nil ->
          nil

        {hour, _n} ->
          days = if MapSet.member?(weekend_hours, hour), do: "Every day", else: "Weekdays"
          "#{days} #{pad(hour)}:00–#{pad(rem(hour + 1, 24))}:00 UTC"
      end

    %{cells: cells, max: cells |> Map.values() |> Enum.max(fn -> 0 end), busiest: busiest}
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  ## Accounts

  @doc """
  Accounts page. Filters: `:q` (handle or display name), `:platform` (feed id),
  `:risk` (`:low | :medium | :high`), `:network` (`"any"`, `"none"` or a network id).
  `:sort` is `:risk` (default, highest first) or `:last_seen` (newest first).
  `:page` is 1-based; pages hold #{@per_page} rows.
  """
  def list_accounts(%State{} = state, params) do
    index = network_index(state)
    q = params[:q] && String.downcase(String.trim(params[:q]))

    matching =
      state.accounts
      |> Map.values()
      |> Enum.filter(fn account ->
        networks = Map.get(index, account.id, [])

        (q in [nil, ""] or String.contains?(String.downcase(account.handle), q) or
           String.contains?(String.downcase(account.display_name || ""), q)) and
          matches?(params, :platform, account.feed_id) and
          matches?(params, :risk, risk_level(account.risk_score)) and
          network_matches?(params[:network], networks)
      end)
      |> sort_accounts(Map.get(params, :sort, :risk))

    total = length(matching)
    pages = max(div(total + @per_page - 1, @per_page), 1)
    page = params |> Map.get(:page, 1) |> max(1) |> min(pages)

    entries =
      matching
      |> Enum.slice((page - 1) * @per_page, @per_page)
      |> Enum.map(&%{account: &1, networks: Map.get(index, &1.id, [])})

    %{entries: entries, total: total, page: page, pages: pages, per_page: @per_page}
  end

  def get_account(%State{} = state, id) do
    with %{} = account <- state.accounts[id] do
      %{
        account: account,
        networks: Map.get(network_index(state), id, []),
        posts: Map.get(state.posts, id, []),
        links: linked_accounts(state, id)
      }
    end
  end

  defp sort_accounts(accounts, :last_seen),
    do: Enum.sort_by(accounts, &{&1.last_seen_at, &1.id}, &later_or_equal?/2)

  defp sort_accounts(accounts, _risk),
    do: Enum.sort_by(accounts, &{-&1.risk_score, &1.id})

  defp network_matches?(nil, _networks), do: true
  defp network_matches?("any", networks), do: networks != []
  defp network_matches?("none", networks), do: networks == []
  defp network_matches?(id, networks), do: Enum.any?(networks, &(&1.id == id))

  # account id => [active networks it belongs to]
  defp network_index(state) do
    for network <- active_networks(state), id <- network.member_ids, reduce: %{} do
      acc -> Map.update(acc, id, [network], &[network | &1])
    end
  end

  defp linked_accounts(state, id) do
    state.links
    |> Enum.filter(fn %Link{account_ids: {a, b}} -> a == id or b == id end)
    |> Enum.group_by(fn %Link{account_ids: {a, b}} -> if a == id, do: b, else: a end)
    |> Enum.map(fn {other, links} ->
      strength = Enum.max_by(links, &@strength_rank[&1.strength]).strength

      %{
        account: state.accounts[other],
        kinds: links |> Enum.map(& &1.kind) |> Enum.uniq(),
        strength: strength
      }
    end)
    |> Enum.reject(&is_nil(&1.account))
    |> Enum.sort_by(&{-@strength_rank[&1.strength], -length(&1.kinds), &1.account.id})
  end

  defp evidence_accounts(state, evidence) do
    evidence
    |> Enum.flat_map(& &1.account_ids)
    |> Enum.uniq()
    |> Enum.map(&state.accounts[&1])
    |> Enum.reject(&is_nil/1)
    |> Map.new(&{&1.id, &1})
  end

  ## Feeds

  @doc """
  Every registered feed with its health and tracked-account count, in registry order.

  A feed reported Healthy whose last item is older than its expected interval is
  shown as Degraded: it has gone quiet. Feeds with no health data are Not connected.
  """
  def feed_health(%State{} = state, now) do
    health = Map.new(state.feed_health, &{&1.feed_id, &1})
    counts = state.accounts |> Map.values() |> Enum.frequencies_by(& &1.feed_id)

    for feed <- Feeds.all() do
      id = feed.id()
      reported = Map.get(health, id, %FeedHealth{feed_id: id, status: :not_connected})

      %{
        feed: feed,
        health: %{reported | status: effective_status(reported, feed, now)},
        accounts: Map.get(counts, id, 0)
      }
    end
  end

  defp effective_status(%FeedHealth{status: :healthy, last_item_at: %DateTime{} = at}, feed, now) do
    if DateTime.diff(now, at) > feed.expected_interval(), do: :degraded, else: :healthy
  end

  defp effective_status(%FeedHealth{status: status}, _feed, _now), do: status

  ## Helpers

  defp matches?(params, key, value), do: is_nil(params[key]) or params[key] == value

  defp later_or_equal?({nil, a}, {nil, b}), do: a >= b
  defp later_or_equal?({nil, _}, _), do: false
  defp later_or_equal?(_, {nil, _}), do: true

  defp later_or_equal?({at_a, a}, {at_b, b}) do
    case DateTime.compare(at_a, at_b) do
      :gt -> true
      :lt -> false
      :eq -> a >= b
    end
  end
end
