defmodule Dripstone.RegistryExtensionTest do
  # Changes application env, so it must not run alongside other tests.
  use ExUnit.Case, async: false

  alias Dripstone.Alerts
  alias Dripstone.Alerts.TriggerType
  alias Dripstone.Feeds
  alias Dripstone.Test.ThrowawayFeed

  setup do
    feeds = Application.get_env(:dripstone, Feeds)
    alerts = Application.get_env(:dripstone, Alerts)

    on_exit(fn ->
      Application.put_env(:dripstone, Feeds, feeds)
      Application.put_env(:dripstone, Alerts, alerts)
    end)

    %{feeds: feeds, alerts: alerts}
  end

  test "a feed registered as docs/FEEDS.md describes appears in the registry", %{feeds: feeds} do
    Application.put_env(:dripstone, Feeds, feeds: feeds[:feeds] ++ [ThrowawayFeed])

    assert List.last(Feeds.all()) == ThrowawayFeed
    assert Feeds.get("threads") == ThrowawayFeed
    assert ThrowawayFeed.profile_url(%{handle: "@alice"}) == "https://www.threads.net/@alice"

    assert ThrowawayFeed.post_url(%{handle: "alice", post_id: "C9x"}) ==
             "https://www.threads.net/@alice/post/C9x"
  end

  test "a trigger type added as docs/TRIGGERS.md describes appears in the catalog",
       %{alerts: alerts} do
    entry = [
      id: "link_rotation",
      name: "Link rotation",
      description: "A network is cycling through many short-lived links."
    ]

    Application.put_env(:dripstone, Alerts, trigger_types: alerts[:trigger_types] ++ [entry])

    assert %TriggerType{id: "link_rotation", name: "Link rotation"} =
             List.last(Alerts.trigger_types())

    assert %TriggerType{name: "Link rotation"} = Alerts.get_trigger_type("link_rotation")
  end

  test "the original registries are restored after each test" do
    refute Feeds.get("threads")
    refute Alerts.get_trigger_type("link_rotation")
  end
end
