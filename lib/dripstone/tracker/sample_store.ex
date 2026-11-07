defmodule Dripstone.Tracker.SampleStore do
  @moduledoc """
  In-memory holder of the tracker `State`, used until persistence exists.

  On start it loads the replayed sample data (unless started with `state:` or
  `load: false`). All changes go through this process one at a time and are
  broadcast on the tracker PubSub topic after they are applied. Reads also run
  inside this process and return only their result. Restarting the app resets the
  state.
  """

  use GenServer

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{Assessments, Graph, Intake, SampleLoader, State}

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

  @doc "Reports a finding through the intake. See `Dripstone.Tracker.report_finding/1`."
  def report_finding(attrs, server \\ __MODULE__),
    do: intake(&Intake.run(&1, attrs, DateTime.utc_now()), server)

  @doc "Records a scorer assessment. See `Dripstone.Tracker.record_assessment/1`."
  def record_assessment(attrs, server \\ __MODULE__),
    do: intake(&Assessments.record(&1, attrs, DateTime.utc_now()), server)

  defp intake(run, server) do
    change(
      fn state ->
        with {:ok, result, new_state} <- run.(state) do
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
        {:reply, {:ok, reply}, new_state}

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

  defp messages(%{action: :ignored}), do: []

  defp messages(%{action: action, alert: alert, network_id: network_id}),
    do: [
      {:network_updated, network_id},
      {if(action == :created, do: :alert_raised, else: :alert_updated), alert}
    ]
end
