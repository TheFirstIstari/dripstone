defmodule Dripstone.Adapters.PoliteTest do
  # async: false — Req.Test stubs are global and the ETS cache is shared.
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

  test "relative url returns {:error, {:invalid_args, _}}" do
    assert {:error, {:invalid_args, _}} = Polite.get("/relative/path", robots: false)
  end

  describe "shared state lives in Polite.Gate" do
    alias Dripstone.Adapters.Polite.Gate

    test "rate slots survive the calling process exiting (Oban jobs are short-lived)" do
      host = "polite-survive-#{System.unique_integer([:positive])}.test"

      task = Task.async(fn -> Gate.reserve(host, 60_000) end)
      assert Task.await(task) == 0

      # A later caller, in another process, still has to wait for that booking.
      assert Gate.reserve(host, 60_000) > 50_000
    end

    test "concurrent callers to one host are spaced by the minimum interval" do
      host = "polite-concurrent-#{System.unique_integer([:positive])}.test"

      waits =
        1..5
        |> Enum.map(fn _ -> Task.async(fn -> Gate.reserve(host, 1_000) end) end)
        |> Enum.map(&Task.await/1)
        |> Enum.sort()

      # One goes now; the others are booked roughly 1s, 2s, 3s, 4s later.
      [first | rest] = waits
      assert first == 0

      rest
      |> Enum.with_index(1)
      |> Enum.each(fn {wait, n} -> assert_in_delta wait, n * 1_000, 200 end)
    end
  end

  test "a date-form Retry-After is honoured" do
    retry_at =
      DateTime.utc_now()
      |> DateTime.add(3, :second)
      |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")

    Req.Test.stub(@stub, fn conn ->
      case conn.request_path do
        "/robots.txt" ->
          Req.Test.text(conn, "User-agent: *\nAllow: /")

        _ ->
          if Process.get(:dated_retry) do
            Req.Test.json(conn, %{"ok" => true})
          else
            Process.put(:dated_retry, true)

            conn
            |> Plug.Conn.put_resp_header("retry-after", retry_at)
            |> Plug.Conn.put_status(429)
            |> Req.Test.json(%{})
          end
      end
    end)

    assert {:ok, %{status: 200}} = Polite.get("http://polite-dated.test/items", opts())
    assert_received {:slept, ms}
    assert ms > 1_000 and ms <= 3_000
  end
end
