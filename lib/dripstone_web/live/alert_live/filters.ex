defmodule DripstoneWeb.AlertLive.Filters do
  @moduledoc """
  Alert inbox filters, shared by the inbox and the alert detail page (which carries
  them so `j`/`k` follow the inbox order).

  URL params are matched against fixed allow-lists, the trigger catalog and the feed
  registry; anything unrecognized is dropped, and no atoms are created from input.
  """

  alias Dripstone.Alerts
  alias Dripstone.Feeds

  @statuses %{
    "open" => :open,
    "confirmed" => :confirmed,
    "dismissed" => :dismissed,
    "all" => :all
  }
  @severities %{"low" => :low, "medium" => :medium, "high" => :high}

  @type t :: %{
          status: :open | :confirmed | :dismissed | :all,
          severity: :low | :medium | :high | nil,
          trigger: String.t() | nil,
          platform: String.t() | nil
        }

  @doc "Parses URL params into filters. Status defaults to `:open`."
  @spec parse(map()) :: t()
  def parse(params) do
    %{
      status: Map.get(@statuses, params["status"], :open),
      severity: Map.get(@severities, params["severity"]),
      trigger: if(Alerts.get_trigger_type(params["trigger"]), do: params["trigger"]),
      platform: if(Feeds.get(params["platform"]), do: params["platform"])
    }
  end

  @doc "Query params for a URL, leaving out defaults and empty filters."
  @spec to_query(t()) :: keyword()
  def to_query(filters) do
    [
      status: if(filters.status != :open, do: Atom.to_string(filters.status)),
      severity: filters.severity && Atom.to_string(filters.severity),
      trigger: filters.trigger,
      platform: filters.platform
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  @doc "Values for the filter form (strings, \"\" for any)."
  @spec form_params(t()) :: map()
  def form_params(filters) do
    %{
      "status" => Atom.to_string(filters.status),
      "severity" => (filters.severity && Atom.to_string(filters.severity)) || "",
      "trigger" => filters.trigger || "",
      "platform" => filters.platform || ""
    }
  end

  @doc "The filters in the shape `Dripstone.Tracker.list_alerts/1` expects."
  @spec to_tracker(t()) :: map()
  def to_tracker(filters), do: Map.reject(filters, fn {_key, value} -> is_nil(value) end)

  @doc "Whether any filter differs from the default inbox."
  def filtered?(filters), do: to_query(filters) != []

  def status_options,
    do: [{"Open", "open"}, {"Confirmed", "confirmed"}, {"Dismissed", "dismissed"}, {"All", "all"}]

  def severity_options, do: [{"High", "high"}, {"Medium", "medium"}, {"Low", "low"}]
  def trigger_options, do: Enum.map(Alerts.trigger_types(), &{&1.name, &1.id})
  def platform_options, do: Enum.map(Feeds.all(), &{&1.name(), &1.id()})
end
