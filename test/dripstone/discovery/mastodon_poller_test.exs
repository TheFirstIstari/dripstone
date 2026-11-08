defmodule Dripstone.Discovery.MastodonPollerTest do
  # Mastodon public-timeline discovery, from recorded statuses (no network).
  use ExUnit.Case, async: true

  alias Dripstone.Discovery.MastodonPoller

  @now ~U[2026-11-08 10:00:00Z]

  defp status(acct, minute, link, extra \\ %{}) do
    Map.merge(
      %{
        "account" => %{"acct" => acct},
        "created_at" => "2026-11-08T10:0#{minute}:00.000Z",
        "content" => ~s(<p>Check <a href="#{link}">#{link}</a></p>)
      },
      extra
    )
  end

  defp feed(statuses, instance \\ "mas.to") do
    Enum.reduce(statuses, {MastodonPoller.new_state(), []}, fn s, {state, found} ->
      {state, c} = MastodonPoller.handle_status(state, s, instance, @now)
      {state, found ++ c}
    end)
  end

  test "five accounts across instances posting one link make a candidate keyed user@instance" do
    statuses =
      for n <- 1..5,
          do: status("bot#{n}@spam#{n}.example", n, "https://promo.example/x?utm_source=m")

    {_state, [candidate]} = feed(statuses)
    assert candidate.url == "https://promo.example/x"
    assert "bot1@spam1.example" in candidate.dids
  end

  test "local accounts get the polled instance as their home" do
    statuses = for n <- 1..5, do: status("local#{n}", n, "https://promo.example/y")
    {_state, [candidate]} = feed(statuses, "mas.to")
    assert "local1@mas.to" in candidate.dids
  end

  test "boosts are skipped (a boost isn't the account posting the link)" do
    statuses =
      for n <- 1..5,
          do:
            status("b#{n}@x.example", n, "https://promo.example/z", %{"reblog" => %{"id" => "1"}})

    {state, []} = feed(statuses)
    assert state.health.items_24h == 0
  end

  test "posts are counted for feed health" do
    {state, []} = feed([status("a@x.example", 1, "https://one.example/")])
    assert state.health.items_24h == 1
  end
end
