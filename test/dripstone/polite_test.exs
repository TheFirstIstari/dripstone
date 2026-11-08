defmodule Dripstone.Adapters.PoliteTest do
  # async: false — Req.Test stubs are global.
  use ExUnit.Case, async: false

  alias Dripstone.Adapters.Polite

  @stub Dripstone.PoliteTestStub

  defp sleep_spy(test_pid) do
    fn ms -> send(test_pid, {:slept, ms}) end
  end

  defp opts(extra \\ []) do
    [plug: {Req.Test, @stub}, min_interval_ms: 0, sleep: sleep_spy(self())] ++ extra
  end

  test "200 returns {:ok, resp} with the configured user agent" do
    Req.Test.stub(@stub, fn conn ->
      send(self(), {:ua, Plug.Conn.get_req_header(conn, "user-agent")})

      case conn.request_path do
        "/robots.txt" -> Req.Test.text(conn, "User-agent: *\nAllow: /")
        _ -> Req.Test.json(conn, %{"ok" => true})
      end
    end)

    assert {:ok, %{status: 200}} = Polite.get("http://polite-ua.test/items", opts())
    assert_received {:ua, ["DripstoneBot/0.1 (+research)"]}
  end

  test "robots Disallow blocks the request without fetching" do
    Req.Test.stub(@stub, fn conn ->
      send(self(), {:hit, conn.request_path})

      case conn.request_path do
        "/robots.txt" -> Req.Test.text(conn, "User-agent: *\nDisallow: /")
        _ -> Req.Test.json(conn, %{})
      end
    end)

    assert {:error, :disallowed_by_robots} =
             Polite.get("http://polite-robots.test/items", opts())

    assert_received {:hit, "/robots.txt"}
    refute_received {:hit, "/items"}
  end

  test "429 retries and honors Retry-After" do
    Req.Test.stub(@stub, fn
      %{request_path: "/robots.txt"} = conn ->
        Req.Test.text(conn, "User-agent: *\nAllow: /")

      conn ->
        if Process.get(:retried) do
          Req.Test.json(conn, %{"ok" => true})
        else
          Process.put(:retried, true)

          conn
          |> Plug.Conn.put_resp_header("retry-after", "2")
          |> Plug.Conn.put_status(429)
          |> Req.Test.json(%{"error" => "slow down"})
        end
    end)

    assert {:ok, %{status: 200}} =
             Polite.get("http://polite-retry.test/items", opts(max_retries: 3))

    assert_received {:slept, 2_000}
  end

  test "persistent 429 returns {:error, {:rate_limited, attempts}}" do
    Req.Test.stub(@stub, fn conn ->
      conn |> Plug.Conn.put_status(429) |> Req.Test.json(%{})
    end)

    assert {:error, {:rate_limited, 3}} =
             Polite.get(
               "http://polite-giveup.test/items",
               opts(max_retries: 2, robots: false)
             )
  end

  test "rate gate sleeps between requests to the same host" do
    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{}) end)
    spy = sleep_spy(self())

    assert {:ok, _} =
             Polite.get("http://polite-gate.test/a",
               plug: {Req.Test, @stub},
               min_interval_ms: 60_000,
               sleep: spy,
               robots: false
             )

    assert {:ok, _} =
             Polite.get("http://polite-gate.test/b",
               plug: {Req.Test, @stub},
               min_interval_ms: 60_000,
               sleep: spy,
               robots: false
             )

    assert_received {:slept, wait}
    assert wait > 0
  end

  test "non-2xx returns {:error, {:http_error, status}}" do
    Req.Test.stub(@stub, fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{})
    end)

    assert {:error, {:http_error, 500}} =
             Polite.get("http://polite-500.test/items", opts(robots: false))
  end

  test "unparseable Retry-After falls back to 1s instead of hammering" do
    Req.Test.stub(@stub, fn
      %{request_path: "/robots.txt"} = conn ->
        Req.Test.text(conn, "User-agent: *\nAllow: /")

      conn ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "not-a-date")
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{})
    end)

    assert {:error, {:rate_limited, 2}} =
             Polite.get("http://polite-bad-retry.test/items", opts(max_retries: 1))

    assert_received {:slept, 1_000}
  end

  test "Disallow before any User-agent section allows the path" do
    Req.Test.stub(@stub, fn conn ->
      send(self(), {:hit, conn.request_path})

      case conn.request_path do
        "/robots.txt" ->
          Req.Test.text(conn, "Disallow: /items\nUser-agent: otherbot\nDisallow: /x")

        _ ->
          Req.Test.json(conn, %{})
      end
    end)

    assert {:ok, %{status: 200}} = Polite.get("http://polite-preagent.test/items", opts())
    assert_received {:hit, "/items"}
  end

  test "failed robots fetch is not cached; next call refetches" do
    Req.Test.stub(@stub, fn conn ->
      count = Process.get(:robots_hits, 0)
      Process.put(:robots_hits, count + 1)

      case conn.request_path do
        "/robots.txt" when count == 0 -> conn |> Plug.Conn.put_status(500) |> Req.Test.text("")
        "/robots.txt" -> Req.Test.text(conn, "User-agent: *\nDisallow: /items")
        _ -> Req.Test.json(conn, %{})
      end
    end)

    assert {:ok, %{status: 200}} = Polite.get("http://polite-flaky-robots.test/other", opts())

    assert {:error, :disallowed_by_robots} =
             Polite.get("http://polite-flaky-robots.test/items", opts())
  end

  test "relative url returns {:error, {:invalid_args, _}}" do
    assert {:error, {:invalid_args, _}} = Polite.get("/relative/path", robots: false)
  end
end
