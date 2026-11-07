defmodule Dripstone.Tracker.SampleLoader do
  @moduledoc """
  Builds a `Dripstone.Tracker.State` from `Dripstone.Tracker.SampleData` by
  loading the base data and replaying every event in order through the real code
  paths: findings through the intake, decisions through `Decisions`, curation
  through `Curation`. Each event is applied at its own timestamp.
  """

  alias Dripstone.Tracker.{Curation, Decisions, Intake, SampleData, State}

  @doc "Generates the sample data relative to `now` and replays it."
  @spec load(DateTime.t()) :: State.t()
  def load(now \\ DateTime.utc_now()) do
    data = SampleData.generate(now)

    base = %State{
      accounts: Map.new(data.accounts, &{&1.id, &1}),
      posts:
        data.posts
        |> Enum.group_by(& &1.account_id)
        |> Map.new(fn {id, posts} ->
          {id, Enum.sort_by(posts, & &1.posted_at, {:desc, DateTime})}
        end),
      links: data.links,
      feed_health: data.feed_health
    }

    Enum.reduce(data.events, base, &replay/2)
  end

  defp replay(%{type: :finding, finding: finding, at: at}, state) do
    case Intake.run(state, finding, at) do
      {:ok, _result, state} -> state
      {:error, errors} -> raise ArgumentError, "invalid sample finding: #{inspect(errors)}"
    end
  end

  defp replay(%{type: :decision, action: action, network_id: id, trigger: trigger} = event, state) do
    alert =
      state.alerts
      |> Map.values()
      |> Enum.find(&(&1.network_id == id and &1.trigger_id == trigger and &1.status == :open))

    fun = if action == :confirm, do: &Decisions.confirm/4, else: &Decisions.dismiss/4
    {:ok, _reply, state, _messages} = fun.(state, alert.id, %{note: event.note}, event.at)
    state
  end

  defp replay(%{type: :curation, action: action, network_id: id, at: at} = event, state) do
    result =
      case action do
        :rename -> Curation.rename(state, id, %{name: event.name}, at)
        :add_tag -> Curation.add_tag(state, id, %{tag: event.tag}, at)
        :remove_member -> Curation.remove_members(state, id, [event.account_id], at)
      end

    {:ok, _reply, state, _messages} = result
    state
  end
end
