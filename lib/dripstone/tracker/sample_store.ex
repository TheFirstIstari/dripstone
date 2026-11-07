defmodule Dripstone.Tracker.SampleStore do
  @moduledoc """
  In-memory holder of the tracker `State`, used until persistence exists.

  On start it loads the replayed sample data (unless started with `state:` or
  `load: false`), or the showcase corpus with `load: :showcase`
  (`Dripstone.Showcase`). All changes go through this process one at a time and are
  broadcast on the tracker PubSub topic after they are applied. Reads also run
  inside this process and return only their result. Restarting the app resets the
  state.
  """

  use GenServer

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{Graph, Intake, Report, Rules, SampleLoader, State}

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Runs `fun.(state)` inside the store and returns its result."
  @spec read((State.t() -> term()), GenServer.server()) :: term()
  def read(fun, server \\ __MODULE__), do: GenServer.call(server, {:read, fun})

  @doc """
  Applies a change. `fun.(state)` returns `{:ok, reply, new_state, messages}` or
  `{:error, reason}`. On success the messages are broadcast and `{:ok, reply}` is
  returned; on error nothing changes.
  """
  @spec change((State.t() -> term()), GenServer.server()) :: {:ok, term()} | {:error, term()}
  def change(fun, server \\ __MODULE__), do: GenServer.call(server, {:change, fun})

  @doc """
  Reports an account, group or trend finding: validates it (`Report`), applies the
  rules (`Rules`) and runs the resulting internal findings through the intake, all in
  one change. See `Dripstone.Tracker.report_finding/1`.
  """
  def report_finding(attrs, server \\ __MODULE__) do
    change(
      fn state ->
        with {:ok, report} <- Report.cast(attrs, state),
             {:ok, result, new_state} <- Rules.run(state, report, DateTime.utc_now()) do
          {:ok, result, new_state, report_messages(result)}
        end
      end,
      server
    )
  end

  @doc false
  # Runs one *internal* finding (`Dripstone.Tracker.Finding`) straight through the
  # intake. Detection never calls this; it exists for tests that need a specific
  # alert, and mirrors how the sample data is replayed.
  def apply_finding(attrs, server \\ __MODULE__) do
    change(
      fn state ->
        with {:ok, result, new_state} <- Intake.run(state, attrs, DateTime.utc_now()) do
          {:ok, result, new_state, messages(result)}
        end
      end,
      server
    )
  end

  @doc "The graph layout for a network, cached per membership."
  def network_graph(network_id, server \\ __MODULE__),
    do: GenServer.call(server, {:graph, network_id}, 30_000)

  @doc "The current state (for tests)."
  def get_state(server \\ __MODULE__), do: GenServer.call(server, :get_state)

  @doc "Replaces the whole state (for tests)."
  def put_state(%State{} = state, server \\ __MODULE__),
    do: GenServer.call(server, {:put_state, state})

  @doc "Regenerates and replays the sample data relative to now."
  def reset(server \\ __MODULE__), do: GenServer.call(server, :reset, 30_000)

  @impl true
  def init(opts) do
    state =
      cond do
        state = Keyword.get(opts, :state) -> state
        Keyword.get(opts, :load, true) == :showcase -> showcase!()
        Keyword.get(opts, :load, true) -> SampleLoader.load()
        true -> %State{}
      end

    {:ok, state}
  end

  @impl true
  def handle_call({:read, fun}, _from, state), do: {:reply, fun.(state), state}

  def handle_call({:change, fun}, _from, state) do
    case fun.(state) do
      {:ok, reply, %State{} = new_state, messages} ->
        Enum.each(messages, &Tracker.broadcast/1)
        # State changed, so any cached graph may be stale.
        {:reply, {:ok, reply}, %{new_state | cache: %{}}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:graph, network_id}, _from, state) do
    case state.networks[network_id] do
      nil ->
        {:reply, nil, state}

      network ->
        key = Graph.cache_key(network)

        case state.cache do
          %{^key => graph} ->
            {:reply, graph, state}

          _miss ->
            graph = Graph.build(network, state.links)
            {:reply, graph, %{state | cache: Map.put(state.cache, key, graph)}}
        end
    end
  end

  def handle_call(:get_state, _from, state), do: {:reply, state, state}
  def handle_call({:put_state, new_state}, _from, _state), do: {:reply, :ok, new_state}
  def handle_call(:reset, _from, _state), do: {:reply, :ok, SampleLoader.load()}

  defp showcase! do
    case Dripstone.Showcase.load() do
      {:ok, state} -> state
      {:error, reason} -> raise "could not load the showcase corpus: #{inspect(reason)}"
    end
  end

  defp report_messages(result) do
    alerts =
      Enum.flat_map(result.alerts, &messages(Map.put(&1, :network_id, &1.alert.network_id)))

    networks = if result.network_id, do: [{:network_updated, result.network_id}], else: []
    accounts = Enum.map(result.account_ids, &{:account_updated, &1})
    Enum.uniq(alerts ++ networks ++ accounts)
  end

  defp messages(%{action: :ignored}), do: []

  defp messages(%{action: action, alert: alert, network_id: network_id}),
    do: [
      {:network_updated, network_id},
      {if(action == :created, do: :alert_raised, else: :alert_updated), alert}
    ]
end
