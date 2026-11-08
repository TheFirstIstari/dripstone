defmodule Dripstone.Adapters.Polite.Gate do
  @moduledoc """
  Long-lived owner of `Dripstone.Adapters.Polite`'s shared state, so it survives
  the short-lived processes (Oban jobs) that make requests:

    * **per-host rate slots.** `reserve/2` atomically books the next allowed
      request time for a host and returns how long the caller must wait first, so
      concurrent callers to one host are spaced by the minimum interval;
    * **the robots.txt cache.** Rules with the time they were fetched, kept for
      `@robots_ttl_ms`.

  Started under the app supervisor. In processes where it isn't running (e.g.
  a bare script), `ensure_started/0` starts it unlinked.
  """

  use GenServer

  @name __MODULE__
  @table Dripstone.Adapters.Polite
  @robots_ttl_ms 24 * 60 * 60 * 1000

  @doc false
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, @name))

  @doc "Starts the gate if it isn't running (outside the app supervisor)."
  @spec ensure_started() :: :ok
  def ensure_started do
    if Process.whereis(@name) do
      :ok
    else
      case GenServer.start(__MODULE__, :ok, name: @name) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
    end
  end

  @doc """
  Books the next request slot for `host` at least `interval_ms` after the previous
  booking. Returns the milliseconds the caller must wait before sending.
  """
  @spec reserve(String.t(), non_neg_integer()) :: non_neg_integer()
  def reserve(host, interval_ms) do
    :ok = ensure_started()
    GenServer.call(@name, {:reserve, host, interval_ms})
  end

  @doc "Cached robots.txt rules for `host`, or `:miss` when absent or older than a day."
  @spec robots(String.t()) :: {:ok, [String.t()]} | :miss
  def robots(host) do
    :ok = ensure_started()

    case :ets.lookup(@table, {:robots, host}) do
      [{_, rules, at}] ->
        if System.monotonic_time(:millisecond) - at < @robots_ttl_ms,
          do: {:ok, rules},
          else: :miss

      _ ->
        :miss
    end
  end

  @doc "Caches robots.txt rules for `host`."
  @spec put_robots(String.t(), [String.t()]) :: :ok
  def put_robots(host, rules) do
    :ok = ensure_started()
    GenServer.call(@name, {:put_robots, host, rules})
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])
    {:ok, nil}
  end

  @impl true
  def handle_call({:reserve, host, interval_ms}, _from, state) do
    now = System.monotonic_time(:millisecond)

    slot =
      case :ets.lookup(@table, {:next, host}) do
        [{_, next}] when next > now -> next
        _ -> now
      end

    :ets.insert(@table, {{:next, host}, slot + interval_ms})
    {:reply, slot - now, state}
  end

  def handle_call({:put_robots, host, rules}, _from, state) do
    :ets.insert(@table, {{:robots, host}, rules, System.monotonic_time(:millisecond)})
    {:reply, :ok, state}
  end
end
