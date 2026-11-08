defmodule Dripstone.Discovery.Caps do
  @moduledoc """
  Limits on live assessment work (live-discovery "Assessment caps"), kept in one
  supervised process so they hold across the short-lived jobs that do the work:

    * at most `groups_per_hour` candidate groups assessed per rolling hour;
    * an account isn't re-assessed within `reassess_ms` of its last assessment.

  Work over a cap is skipped and counted (`skipped/0`), never queued.
  """

  use GenServer

  @name __MODULE__
  @defaults [groups_per_hour: 20, reassess_ms: 24 * 60 * 60 * 1000]
  @hour 60 * 60 * 1000

  @doc false
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: @name)

  @doc "Books one candidate group if the hourly cap allows it: `:ok` or `:over_cap`."
  @spec take_group() :: :ok | :over_cap
  def take_group, do: GenServer.call(@name, :take_group)

  @doc "The accounts (by permanent id) not assessed recently; marks them as assessed now."
  @spec fresh(Enumerable.t()) :: [String.t()]
  def fresh(ids), do: GenServer.call(@name, {:fresh, Enum.to_list(ids)})

  @doc "How many groups and accounts were skipped over a cap since start."
  @spec skipped() :: %{groups: non_neg_integer(), accounts: non_neg_integer()}
  def skipped, do: GenServer.call(@name, :skipped)

  @doc false
  # Tests only.
  def reset(opts \\ []), do: GenServer.call(@name, {:reset, opts})

  @impl true
  def init(opts), do: {:ok, fresh_state(opts)}

  @impl true
  def handle_call(:take_group, _from, s) do
    now = now()
    recent = Enum.filter(s.groups, &(&1 > now - @hour))

    if length(recent) < s.config[:groups_per_hour] do
      {:reply, :ok, %{s | groups: [now | recent]}}
    else
      {:reply, :over_cap,
       %{s | groups: recent, skipped: Map.update!(s.skipped, :groups, &(&1 + 1))}}
    end
  end

  def handle_call({:fresh, ids}, _from, s) do
    now = now()
    {fresh, stale} = Enum.split_with(Enum.uniq(ids), &(not recent?(s, &1, now)))
    assessed = Map.merge(s.assessed, Map.new(fresh, &{&1, now}))

    {:reply, fresh,
     %{
       s
       | assessed: assessed,
         skipped: Map.update!(s.skipped, :accounts, &(&1 + length(stale)))
     }}
  end

  def handle_call(:skipped, _from, s), do: {:reply, s.skipped, s}
  def handle_call({:reset, opts}, _from, _s), do: {:reply, :ok, fresh_state(opts)}

  defp fresh_state(opts) do
    config =
      @defaults
      |> Keyword.merge(Application.get_env(:dripstone, __MODULE__, []))
      |> Keyword.merge(opts)

    %{config: config, groups: [], assessed: %{}, skipped: %{groups: 0, accounts: 0}}
  end

  defp recent?(s, id, now) do
    case s.assessed do
      %{^id => at} -> now - at < s.config[:reassess_ms]
      _ -> false
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
