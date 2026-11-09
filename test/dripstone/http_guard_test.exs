defmodule Dripstone.Test.HttpGuardTest do
  # async: false — asserts the global Req default (see test_helper.exs).
  use ExUnit.Case, async: false

  test "unstubbed HTTP raises instead of hitting the network" do
    assert_raise RuntimeError, ~r/network disabled in tests/, fn ->
      Req.get!("http://127.0.0.1:9/unreachable")
    end
  end

  test "explicit plug opts still work under the guard" do
    plug = fn conn -> Req.Test.json(conn, %{"ok" => true}) end

    assert {:ok, %{status: 200, body: %{"ok" => true}}} =
             Req.get("http://example.test/x", plug: plug)
  end

  test "offline adapters stay green under the guard" do
    assert {:ok, [_ | _]} = Dripstone.Adapters.StubX.fetch_posts("@someone")
    assert {:ok, [_ | _]} = Dripstone.Adapters.StubReddit.fetch_posts("u/someone")
  end
end
