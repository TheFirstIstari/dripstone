defmodule Dripstone.AdaptersTest do
  use ExUnit.Case, async: true

  test "registry exposes both stubs" do
    all = Dripstone.Adapters.all()
    assert all[:stub_x] == Dripstone.Adapters.StubX
    assert all[:stub_reddit] == Dripstone.Adapters.StubReddit
    assert Dripstone.Adapters.get(:stub_x) == Dripstone.Adapters.StubX
    assert Dripstone.Adapters.get("stub_reddit") == Dripstone.Adapters.StubReddit
    assert Dripstone.Adapters.get(:nope) == nil
    assert Dripstone.Adapters.get("nope") == nil
  end

  test "stub_x returns canonical posts with opaque handle" do
    assert {:ok, posts} = Dripstone.Adapters.StubX.fetch_posts("@someone")
    assert length(posts) == 4
    assert Enum.all?(posts, &(&1.handle == "@someone"))

    first = hd(posts)
    assert %{id: "x1", urls: ["https://example.com/ship"]} = first
    assert %DateTime{} = first.published_at
    assert is_binary(first.text)
  end

  test "stub_reddit returns canonical posts with opaque handle" do
    assert {:ok, posts} = Dripstone.Adapters.StubReddit.fetch_posts("u/someone")
    assert length(posts) == 3
    assert Enum.all?(posts, &(&1.handle == "u/someone"))

    first = hd(posts)
    assert first.id == "r1"
    assert first.urls == ["https://example.com/ship"]
    assert String.contains?(first.text, "Tracker launch")
    assert %DateTime{} = first.published_at
  end

  test "stubs return error tuple on missing fixture" do
    assert {:error, _} =
             Dripstone.Adapters.StubX.fetch_posts("h", fixture_path: "/nonexistent.json")

    assert {:error, _} =
             Dripstone.Adapters.StubReddit.fetch_posts("h", fixture_path: "/nonexistent.json")
  end
end
