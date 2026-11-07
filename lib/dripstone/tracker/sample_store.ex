defmodule Dripstone.Tracker.SampleStore do
  @moduledoc """
  In-memory holder of the tracker `State`, used until persistence exists.

  All changes go through this process, one at a time, and are broadcast on the
  tracker PubSub topic after they are applied. Restarting the app resets the state.
  """

  use GenServer

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{Intake, State}

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, Keyword.get(opts, :state, %State{}),
      name: Keyword.get(opts, :name, __MODULE__)
    )
  end

  @doc "Reports a finding through the intake. See `Dripstone.Tracker.report_finding/1`."
  @spec report_finding(map(), GenServer.server()) ::
          {:ok, Intake.result()} | {:error, map()}
  def report_finding(attrs, server \\ __MODULE__),
    do: GenServer.call(server, {:report_finding, attrs})

  @doc "The current state (for reads and tests)."
  @spec get_state(GenServer.server()) :: State.t()
  def get_state(server \\ __MODULE__), do: GenServer.call(server, :get_state)

  @doc "Replaces the whole state. Used to reset between tests."
  @spec put_state(State.t(), GenServer.server()) :: :ok
  def put_state(%State{} = state, server \\ __MODULE__),
    do: GenServer.call(server, {:put_state, state})

  @impl true
  def init(%State{} = state), do: {:ok, state}

  @impl true
  def handle_call({:report_finding, attrs}, _from, state) do
    case Intake.run(state, attrs, DateTime.utc_now()) do
      {:ok, result, new_state} ->
        broadcast_result(result)
        {:reply, {:ok, result}, new_state}

      {:error, errors} ->
        {:reply, {:error, errors}, state}
    end
  end

  def handle_call(:get_state, _from, state), do: {:reply, state, state}
  def handle_call({:put_state, new_state}, _from, _state), do: {:reply, :ok, new_state}

  defp broadcast_result(%{action: :ignored}), do: :ok

  defp broadcast_result(%{action: action, alert: alert, network_id: network_id}) do
    Tracker.broadcast({:network_updated, network_id})
    Tracker.broadcast({if(action == :created, do: :alert_raised, else: :alert_updated), alert})
  end
end
