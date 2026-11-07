defmodule Dripstone.Tracker do
  @moduledoc """
  The tracker context: the one interface the UI uses, and the one entry point
  detection reports findings through.

  Backed by `Dripstone.Tracker.SampleStore` for now; the functions are meant to
  keep their signatures when real storage replaces it.

  Changes are broadcast on the `"tracker"` PubSub topic:

    * `{:alert_raised, alert}`: a new alert
    * `{:alert_updated, alert}`: an existing alert changed
    * `{:network_updated, network_id}`: a network changed
  """

  alias Dripstone.Tracker.SampleStore

  @topic "tracker"

  @doc """
  Reports a finding from detection. See `docs/DETECTION_INTERFACE.md` for the
  fields and results.
  """
  @spec report_finding(map()) :: {:ok, map()} | {:error, %{atom() => [String.t()]}}
  def report_finding(attrs), do: SampleStore.report_finding(attrs)

  @doc "Subscribes the calling process to tracker changes."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(Dripstone.PubSub, @topic)

  @doc false
  def broadcast(message), do: Phoenix.PubSub.broadcast(Dripstone.PubSub, @topic, message)
end
