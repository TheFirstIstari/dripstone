defmodule Dripstone.FeedsTest do
  use ExUnit.Case, async: true

  alias Dripstone.Feeds

  alias Dripstone.Feeds.{Bluesky, Facebook, Mastodon, Reddit, Telegram, X}

  describe "registry" do
    test "all/0 returns the configured feeds in order" do
      assert Feeds.all() == [X, Reddit, Bluesky, Mastodon, Telegram, Facebook]
    end

    test "get/1 finds a feed by its string id" do
      assert Feeds.get("mastodon") == Mastodon
      assert Feeds.get("x") == X
    end

    test "get/1 returns nil for unknown or non-string ids" do
      assert Feeds.get("nope") == nil
      assert Feeds.get(nil) == nil
      assert Feeds.get(:x) == nil
    end

    test "every feed has a unique id, a name and a positive interval" do
      ids = Enum.map(Feeds.all(), & &1.id())
      assert ids == Enum.uniq(ids)

      for feed <- Feeds.all() do
        assert is_binary(feed.name()) and feed.name() != ""
        assert is_integer(feed.expected_interval()) and feed.expected_interval() > 0
      end
    end
  end

  describe "X" do
    test "handles and links" do
      assert X.format_handle(%{handle: "sunny_deals"}) == "@sunny_deals"
      assert X.format_handle(%{handle: "@sunny_deals"}) == "@sunny_deals"
      assert X.profile_url(%{handle: "sunny_deals"}) == "https://x.com/sunny_deals"

      assert X.post_url(%{handle: "sunny_deals", post_id: "1789"}) ==
               "https://x.com/sunny_deals/status/1789"
    end
  end

  describe "Reddit" do
    test "handles and links" do
      assert Reddit.format_handle(%{handle: "k_morgan"}) == "u/k_morgan"
      assert Reddit.format_handle(%{handle: "u/k_morgan"}) == "u/k_morgan"

      assert Reddit.profile_url(%{handle: "/u/k_morgan"}) ==
               "https://www.reddit.com/user/k_morgan"

      assert Reddit.post_url(%{handle: "k_morgan", post_id: "1abc2d"}) ==
               "https://www.reddit.com/comments/1abc2d"
    end
  end

  describe "Bluesky" do
    test "handles and links" do
      assert Bluesky.format_handle(%{handle: "alice.bsky.social"}) == "@alice.bsky.social"

      assert Bluesky.profile_url(%{handle: "alice.bsky.social"}) ==
               "https://bsky.app/profile/alice.bsky.social"

      assert Bluesky.post_url(%{handle: "alice.bsky.social", post_id: "3kxyz"}) ==
               "https://bsky.app/profile/alice.bsky.social/post/3kxyz"
    end
  end

  describe "Mastodon" do
    test "user on an instance is shown as @user@instance and links to that instance" do
      account = %{handle: "alice", instance: "example.social"}

      assert Mastodon.format_handle(account) == "@alice@example.social"
      assert Mastodon.profile_url(account) == "https://example.social/@alice"

      assert Mastodon.post_url(Map.put(account, :post_id, "1123")) ==
               "https://example.social/@alice/1123"
    end

    test "accepts a full user@instance handle" do
      account = %{handle: "@alice@Example.Social"}

      assert Mastodon.format_handle(account) == "@alice@example.social"
      assert Mastodon.profile_url(account) == "https://example.social/@alice"
    end

    test "builds no link when the instance is missing or not a valid host" do
      assert Mastodon.format_handle(%{handle: "alice"}) == "@alice"
      assert Mastodon.profile_url(%{handle: "alice"}) == nil
      assert Mastodon.profile_url(%{handle: "alice", instance: "evil.example/phish?x="}) == nil
      assert Mastodon.post_url(%{handle: "alice@not a host", post_id: "1"}) == nil
    end
  end

  describe "Telegram" do
    test "handles and links" do
      assert Telegram.format_handle(%{handle: "deal_channel"}) == "@deal_channel"
      assert Telegram.profile_url(%{handle: "deal_channel"}) == "https://t.me/deal_channel"

      assert Telegram.post_url(%{handle: "deal_channel", post_id: "482"}) ==
               "https://t.me/deal_channel/482"
    end
  end

  describe "Facebook" do
    test "handles and links" do
      assert Facebook.format_handle(%{handle: "SunnyDealsPage"}) == "SunnyDealsPage"

      assert Facebook.profile_url(%{handle: "SunnyDealsPage"}) ==
               "https://www.facebook.com/SunnyDealsPage"

      assert Facebook.post_url(%{handle: "SunnyDealsPage", post_id: "pfbid02x"}) ==
               "https://www.facebook.com/SunnyDealsPage/posts/pfbid02x"
    end
  end

  describe "link safety" do
    test "path segments from external data are percent-encoded" do
      assert X.profile_url(%{handle: "../admin?x=1"}) == "https://x.com/..%2Fadmin%3Fx%3D1"
      assert X.post_url(%{handle: "a", post_id: "1/../../evil"}) =~ "1%2F..%2F..%2Fevil"
    end

    test "missing values produce no link" do
      assert X.profile_url(%{handle: ""}) == nil
      assert X.post_url(%{handle: "a", post_id: ""}) == nil
      assert Telegram.post_url(%{handle: "a", post_id: nil}) == nil
    end
  end
end
