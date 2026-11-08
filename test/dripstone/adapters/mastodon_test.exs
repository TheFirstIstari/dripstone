defmodule Dripstone.Adapters.MastodonTest do
  # Global Req.Test stub: not async.
  use ExUnit.Case, async: false

  alias Dripstone.Adapters.Mastodon

  @stub Dripstone.MastodonTestStub

  defp opts,
    do: [plug: {Req.Test, @stub}, min_interval_ms: 0, robots: false, sleep: fn _ -> :ok end]

  defp status(id, html, extra \\ %{}),
    do:
      Map.merge(
        %{"id" => id, "content" => html, "created_at" => "2026-11-08T10:00:00.000Z"},
        extra
      )

  test "fetches an account's recent posts from its home instance, no credentials" do
    Req.Test.stub(@stub, fn conn ->
      send(
        self(),
        {:req, conn.host, conn.request_path, Plug.Conn.get_req_header(conn, "authorization")}
      )

      case conn.request_path do
        "/api/v1/accounts/lookup" ->
          Req.Test.json(conn, %{"id" => "42", "display_name" => "Alice"})

        "/api/v1/accounts/42/statuses" ->
          Req.Test.json(conn, [
            status(
              "1",
              ~s(<p>Deal &amp; more <a href="https://deals.example/x?a=1&amp;b=2" rel="nofollow">deals.example/x</a></p>)
            ),
            status(
              "2",
              ~s(<p>Hi <a href="https://m.example/@bob" class="u-url mention">@bob</a> <a href="https://m.example/tags/x" class="mention hashtag">#x</a></p>),
              %{"card" => %{"url" => "https://news.example/y"}}
            )
          ])
      end
    end)

    assert {:ok, [p1, p2]} = Mastodon.fetch_posts("@alice@social.example", opts())

    assert %{id: "1", handle: "alice@social.example", text: "Deal & more deals.example/x"} = p1
    assert p1.urls == ["https://deals.example/x?a=1&b=2"]
    # Mentions and hashtags aren't outbound links; the card is.
    assert p2.urls == ["https://news.example/y"]

    assert_received {:req, "social.example", "/api/v1/accounts/lookup", []}
  end

  test "handles split into user and instance" do
    assert Mastodon.split("@alice@Social.Example") == {:ok, "alice", "social.example"}
    assert Mastodon.split("bob", "mas.to") == {:ok, "bob", "mas.to"}
    assert {:error, _} = Mastodon.split("bob")
  end
end
