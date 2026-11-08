defmodule Dripstone.Workers.DiscoverWorkerTest do
  # live-discovery "Candidates become findings" and "Assessment caps" scenarios.
  # Global Req.Test stub, app config and Live rows: not async.
  use Dripstone.DataCase, async: false
  use Oban.Testing, repo: Dripstone.Repo

  @moduletag :capture_log

  alias Dripstone.Discovery.Caps
  alias Dripstone.Tracker
  alias Dripstone.Tracker.Store
  alias Dripstone.Workers.DiscoverWorker

  @stub Dripstone.DiscoverWorkerStub

  setup do
    worker = Application.get_env(:dripstone, DiscoverWorker, [])
    ai = Application.get_env(:dripstone, Dripstone.AIClient, [])

    Application.put_env(:dripstone, DiscoverWorker,
      http_opts: [
        plug: {Req.Test, @stub},
        min_interval_ms: 0,
        robots: false,
        sleep: fn _ -> :ok end
      ],
      ai_opts: [plug: {Req.Test, @stub}]
    )

    Application.put_env(
      :dripstone,
      Dripstone.AIClient,
      Keyword.merge(ai, api_key: "test", base_url: "http://ai.test")
    )

    Caps.reset()

    on_exit(fn ->
      Application.put_env(:dripstone, DiscoverWorker, worker)
      Application.put_env(:dripstone, Dripstone.AIClient, ai)
      Caps.reset()
    end)

    :ok
  end

  # Bluesky AppView + Jev, one stub. `unreachable` handles answer 500.
  defp stub(coordinated, unreachable \\ []) do
    Req.Test.stub(@stub, fn conn ->
      case conn.request_path do
        "/xrpc/app.bsky.actor.getProfiles" ->
          actors = conn.query_string |> URI.query_decoder() |> Enum.map(fn {_, v} -> v end)

          Req.Test.json(conn, %{
            "profiles" =>
              Enum.map(
                actors,
                &%{"did" => &1, "handle" => String.replace(&1, "did:plc:", "") <> ".bsky.social"}
              )
          })

        "/xrpc/app.bsky.feed.getAuthorFeed" ->
          actor = URI.decode_query(conn.query_string)["actor"]

          if actor in unreachable do
            conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{})
          else
            Req.Test.json(conn, %{"feed" => posts(actor)})
          end

        "/systemone" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          questions = Jason.decode!(body)["questions"]

          answers =
            Map.new(questions, fn
              {"coordinated", _} ->
                {"coordinated", %{"type" => "noul", "noul" => coordinated}}

              {"relation", _} ->
                {"relation",
                 %{"type" => "choice", "choice" => "shared-link", "confidence" => 0.8}}

              {name, %{"type" => "noul"}} ->
                {name, %{"type" => "noul", "noul" => 0.9}}

              {name, %{"type" => "choice"}} ->
                {name, %{"type" => "choice", "choice" => "other", "confidence" => 0.5}}

              {name, %{"type" => "score"}} ->
                {name,
                 %{
                   "type" => "score",
                   "score" => 1,
                   "legend" => %{"0" => "a", "1" => "b", "2" => "c"}
                 }}
            end)

          Req.Test.json(conn, %{"answers" => answers})
      end
    end)
  end

  defp posts(actor) do
    for n <- 1..3 do
      %{
        "post" => %{
          "uri" => "at://did:plc:#{actor}/app.bsky.feed.post/#{actor}-#{n}",
          "author" => %{"handle" => actor},
          "record" => %{
            "text" => "Deal #{n}",
            "createdAt" => "2026-11-08T09:0#{n}:00Z",
            "facets" => [
              %{
                "features" => [
                  %{"$type" => "app.bsky.richtext.facet#link", "uri" => "https://deals.example/x"}
                ]
              }
            ]
          }
        }
      }
    end
  end

  defp dids(n), do: for(i <- 1..n, do: "did:plc:ring#{i}-#{System.unique_integer([:positive])}")

  test "a coordinated candidate group raises a real alert in Live (A candidate group raises a real alert)" do
    stub(0.9)
    :ok = Tracker.subscribe()
    group = dids(5)

    assert :ok =
             perform_job(DiscoverWorker, %{
               "url" => "https://deals.example/x",
               "domain" => "deals.example",
               "dids" => group
             })

    assert_receive {:alert_raised, %{trigger_id: "new_network", model: _} = alert}
    {:ok, state} = Store.load()
    network = state.networks[alert.network_id]
    assert length(network.member_ids) == 5
    assert network.main_domain == "deals.example"
    assert Enum.all?(network.member_ids, &(state.accounts[&1].external_id in group))
  end

  test "an unreachable account is left out and the rest are assessed (Unreachable account)" do
    [a, b, c] = group = dids(3)
    stub(0.9, [String.replace(c, "did:plc:", "") <> ".bsky.social"])
    :ok = Tracker.subscribe()

    assert :ok =
             perform_job(DiscoverWorker, %{
               "url" => "https://u.example/",
               "domain" => "u.example",
               "dids" => group
             })

    assert_receive {:alert_raised, %{network_id: id}}
    {:ok, state} = Store.load()
    externals = Enum.map(state.networks[id].member_ids, &state.accounts[&1].external_id)
    assert Enum.sort(externals) == Enum.sort([a, b])
  end

  test "over the hourly cap a group is skipped, not queued (Hourly cap reached)" do
    stub(0.9)
    Caps.reset(groups_per_hour: 1)

    assert :ok =
             perform_job(DiscoverWorker, %{"url" => "https://one.example/", "dids" => dids(2)})

    assert :ok =
             perform_job(DiscoverWorker, %{"url" => "https://two.example/", "dids" => dids(2)})

    assert Caps.skipped().groups == 1
  end

  test "a large burst is trimmed to the group size limit (Large burst trimmed)" do
    stub(0.9)
    :ok = Tracker.subscribe()

    assert :ok =
             perform_job(DiscoverWorker, %{"url" => "https://big.example/", "dids" => dids(40)})

    assert_receive {:alert_raised, %{network_id: id}}
    {:ok, state} = Store.load()
    assert length(state.networks[id].member_ids) == 10
  end

  test "accounts assessed recently aren't assessed again" do
    stub(0.9)
    group = dids(3)
    assert Caps.fresh(group) == group
    assert Caps.fresh(group) == []
    assert Caps.skipped().accounts == 3
  end
end
