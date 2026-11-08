defmodule Dripstone.Tracker.DemoStore do
  @moduledoc """
  The Demo dataset: one tracker `State` held in memory only, never written to the
  database (see `openspec/specs/data-modes`). It starts on demand under
  `Dripstone.Tracker.DemoSupervisor` the first time anything uses Demo, seeded from
  the sample data, together with the simulator targeting Demo (unless
  `config :dripstone, :demo_simulator, false`).

  `Dripstone.Tracker.Store` routes `load/0`, `save/1` and `write/1` here when the
  calling process's dataset is `:demo`. Writes run inside this process one at a
  time, the same way `Tracker.Writer` serialises Live writes.
  """

  use GenServer

  alias Dripstone.Tracker.{SampleLoader, Simulator, State}

  @name __MODULE__
  @state_key :dripstone_demo_state

  @doc "Starts the Demo store (and its simulator) unless it is already running."
  @spec ensure_started() :: :ok
  def ensure_started do
    if Process.whereis(@name) do
      :ok
    else
      case DynamicSupervisor.start_child(Dripstone.Tracker.DemoSupervisor, {__MODULE__, []}) do
        {:ok, _pid} -> start_simulator()
        {:error, {:already_started, _pid}} -> :ok
      end
    end
  end

  @doc false
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: @name)

  @doc "The current Demo state."
  @spec load() :: State.t()
  def load do
    if inside?(), do: Process.get(@state_key), else: call(:get)
  end

  @doc "Replaces the Demo state."
  @spec save(State.t()) :: :ok
  def save(%State{} = state) do
    if inside?() do
      Process.put(@state_key, state)
      :ok
    else
      call({:put, state})
    end
  end

  @doc "Runs a load-modify-save closure as the Demo dataset's single writer."
  @spec run((-> result)) :: result when result: var
  def run(fun) do
    if inside?(), do: fun.(), else: call({:run, fun})
  end

  @impl true
  def init(:ok), do: {:ok, SampleLoader.load()}

  @impl true
  def handle_call(:get, _from, state), do: {:reply, state, state}
  def handle_call({:put, new_state}, _from, _state), do: {:reply, :ok, new_state}

  def handle_call({:run, fun}, _from, state) do
    Process.put(:dripstone_dataset, :demo)
    Process.put(@state_key, state)
    reply = fun.()
    {:reply, reply, Process.get(@state_key)}
  end

  defp call(message) do
    :ok = ensure_started()
    GenServer.call(@name, message, :infinity)
  end

  defp inside?, do: self() == Process.whereis(@name)

  defp start_simulator do
    if Application.get_env(:dripstone, :demo_simulator, true) and
         is_nil(Process.whereis(Simulator)) do
      case DynamicSupervisor.start_child(
             Dripstone.Tracker.DemoSupervisor,
             {Simulator, dataset: :demo}
           ) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
    else
      :ok
    end
  end
end
