defmodule Dripstone.AIClientTest do
  # async: false — Req.Test stubs are global.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  @stub Dripstone.AIClientTestStub

  setup do
    old = Application.get_env(:dripstone, Dripstone.AIClient, [])

    Application.put_env(:dripstone, Dripstone.AIClient,
      base_url: "http://ai.test",
      model: "test-model",
      api_key: "test-key"
    )

    on_exit(fn -> Application.put_env(:dripstone, Dripstone.AIClient, old) end)
    :ok
  end

  defp questions, do: %{is_bot: %{type: :noul, instructions: "Is this a bot?"}}

  defp stub_capture(test_pid, reply) do
    Req.Test.stub(@stub, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)

      send(
        test_pid,
        {:ai_request, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"),
         Jason.decode!(raw)}
      )

      reply.(conn)
    end)
  end

  test "200 with answers map returns {:ok, answers} with bearer auth to /systemone" do
    stub_capture(self(), fn conn ->
      Req.Test.json(conn, %{
        "model" => "test-model",
        "answers" => %{"is_bot" => %{"type" => "noul", "noul" => 0.91}},
        "usage" => %{}
      })
    end)

    assert {:ok, %{"is_bot" => %{"type" => "noul", "noul" => 0.91}}} =
             Dripstone.AIClient.decide("some state", questions(), plug: {Req.Test, @stub})

    assert_received {:ai_request, path, ["Bearer test-key"], body}
    assert String.ends_with?(path, "/systemone")
    assert body["model"] == "test-model"
    assert body["state"] == "some state"

    assert body["questions"] == %{
             "is_bot" => %{"type" => "noul", "instructions" => "Is this a bot?"}
           }
  end

  test "200 with wrong shape returns {:error, _}" do
    stub_capture(self(), fn conn -> Req.Test.json(conn, %{"model" => "test-model"}) end)

    assert capture_log(fn ->
             assert {:error, :bad_response} =
                      Dripstone.AIClient.decide("state", questions(), plug: {Req.Test, @stub})
           end) =~ "AIClient"
  end

  test "non-200 returns {:error, {:http_error, status}}" do
    stub_capture(self(), fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"detail" => "boom"})
    end)

    assert capture_log(fn ->
             assert {:error, {:http_error, 500}} =
                      Dripstone.AIClient.decide("state", questions(), plug: {Req.Test, @stub})
           end) =~ "AIClient"
  end

  test "transport error returns {:error, _}" do
    Req.Test.stub(@stub, fn conn -> Req.Test.transport_error(conn, :timeout) end)

    assert capture_log(fn ->
             assert {:error, {:transport, _}} =
                      Dripstone.AIClient.decide("state", questions(), plug: {Req.Test, @stub})
           end) =~ "AIClient"
  end

  test "state over 8000 chars is truncated before send" do
    stub_capture(self(), fn conn -> Req.Test.json(conn, %{"answers" => %{}}) end)

    assert {:ok, %{}} =
             Dripstone.AIClient.decide(String.duplicate("x", 9_000), questions(),
               plug: {Req.Test, @stub}
             )

    assert_received {:ai_request, _, _, %{"state" => sent}}
    assert String.length(sent) == 8_000
  end

  test "missing api key fails closed without any request" do
    Req.Test.stub(@stub, fn _conn -> raise "must not POST without an api key" end)

    for missing <- [nil, ""] do
      Application.put_env(:dripstone, Dripstone.AIClient,
        base_url: "http://ai.test",
        model: "test-model",
        api_key: missing
      )

      assert capture_log(fn ->
               assert {:error, :missing_api_key} =
                        Dripstone.AIClient.decide("state", questions(), plug: {Req.Test, @stub})
             end) =~ "AIClient"
    end

    refute_received {:ai_request, _, _, _}
  end

  test "non-binary state returns {:error, {:invalid_args, _}}" do
    Req.Test.stub(@stub, fn _conn -> raise "must not POST with invalid args" end)

    assert {:error, {:invalid_args, _}} =
             Dripstone.AIClient.decide(123, questions(), plug: {Req.Test, @stub})
  end

  test "non-map questions returns {:error, {:invalid_args, _}}" do
    Req.Test.stub(@stub, fn _conn -> raise "must not POST with invalid args" end)

    assert {:error, {:invalid_args, _}} =
             Dripstone.AIClient.decide("state", [:not, :a, :map], plug: {Req.Test, @stub})
  end

  test "more than 32 questions returns {:error, {:invalid_args, _}}" do
    Req.Test.stub(@stub, fn _conn -> raise "must not POST with invalid args" end)

    too_many =
      Map.new(1..33, fn i -> {"q#{i}", %{type: :noul, instructions: "?"}} end)

    assert {:error, {:invalid_args, _}} =
             Dripstone.AIClient.decide("state", too_many, plug: {Req.Test, @stub})
  end
end
