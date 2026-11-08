defmodule Dripstone.Tracker.Writer do
  @moduledoc false
  # Single-writer serializer for the tracker. `GenServer.call/3` queues
  # concurrent writers, so each load-modify-save closure runs alone and no
  # update is lost. Started under the app supervisor; started lazily in tests.

  use GenServer

  @name __MODULE__

  @spec run((-> result)) :: result when result: var
  def run(fun) do
    ensure_started()
    GenServer.call(@name, {:run, fun}, :infinity)
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, @name))

  @impl true
  def init(:ok), do: {:ok, nil}

  @impl true
  def handle_call({:run, fun}, _from, state), do: {:reply, fun.(), state}

  defp ensure_started do
    case GenServer.whereis(@name) do
      nil ->
        case start_link() do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
        end

      _pid ->
        :ok
    end
  end
end
