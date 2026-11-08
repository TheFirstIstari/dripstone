defmodule Dripstone.Workers.TrendWorkerTest do
  # live-discovery "Trend re-checks". Global Req.Test stub, app config, Live rows.
  use Dripstone.DataCase, async: false
  use Oban.Testing, repo: Dripstone.Repo

  @moduletag :capture_log

  alias Dripstone.Tracker.{Account, Network, Post, State, Store}
  alias Dripstone.Workers.TrendWorker

  @stub Dripstone.TrendWorkerStub

  setup do
    worker = Application.get_env(:dripstone, TrendWorker, [])
    ai = Application.get_env(:dripstone, Dripstone.AIClient, [])
    Application.put_env(:dripstone, TrendWorker, ai_opts: [plug: {Req.Test, @stub}])

    Application.put_env(
      :dripstone,
      Dripstone.AIClient,
      Keyword.merge(ai, api_key: "test", base_url: "http://ai.test")
    )

    on_exit(fn ->
      Application.put_env(:dripstone, TrendWorker, worker)
      Application.put_env(:dripstone, Dripstone.AIClient, ai)
    end)

    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{
        "answers" => %{
          "increasing" => %{"type" => "noul", "noul" => 0.9},
          "trajectory" => %{"type" => "choice", "choice" => "forming", "confidence" => 0.8}
        }
      })
    end)

    :ok
  end

  defp network(id, account_id, posted_ago_s) do
    at = DateTime.utc_now() |> DateTime.add(-posted_ago_s, :second) |> DateTime.truncate(:second)

    {%Network{id: id, name: id, member_ids: [account_id], platforms: ["bluesky"]},
     %Account{id: account_id, feed_id: "bluesky", handle: "#{account_id}.bsky.social"},
     %Post{
       id: "post-#{account_id}",
       account_id: account_id,
       post_id: "p1",
       posted_at: at,
       text: "x"
     }}
  end

  test "active live networks are re-checked and inactive ones skipped (Active network re-checked)" do
    {active, a1, p1} = network("net-active", "acc-a", 3_600)
    {quiet, a2, p2} = network("net-quiet", "acc-q", 3 * 86_400)

    :ok =
      Store.save(%State{
        accounts: %{a1.id => a1, a2.id => a2},
        account_by_handle: %{{"bluesky", a1.handle} => a1.id, {"bluesky", a2.handle} => a2.id},
        networks: %{active.id => active, quiet.id => quiet},
        posts: %{a1.id => [p1], a2.id => [p2]}
      })

    assert :ok = perform_job(TrendWorker, %{})

    {:ok, state} = Store.load()
    trend_networks = for %{kind: :trend, network_id: id} <- state.findings, do: id
    assert trend_networks == ["net-active"]
    assert state.networks["net-active"].assessment.trajectory == "forming"
    assert is_nil(state.networks["net-quiet"].assessment)
  end

  test "the trend re-check is scheduled every 6 hours, in production too" do
    plugins = Application.get_env(:dripstone, Oban) |> Keyword.get(:plugins, [])
    assert {Oban.Plugins.Cron, crontab: [{"0 */6 * * *", TrendWorker}]} in plugins

    # runtime.exs re-asserts the Oban config for releases; it must keep the cron.
    assert File.read!("config/runtime.exs") =~ ~s({"0 */6 * * *", Dripstone.Workers.TrendWorker})
  end
end
