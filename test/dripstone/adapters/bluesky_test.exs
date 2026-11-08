defmodule Dripstone.Adapters.BlueskyTest do
  # live-discovery "Bluesky fetcher" scenarios. Req.Test stubs are global: not async.
  use ExUnit.Case, async: false

  alias Dripstone.Adapters.Bluesky

  @stub Dripstone.BlueskyTestStub

  defp opts(extra \\ []),
    do:
      [plug: {Req.Test, @stub}, min_interval_ms: 0, robots: false, sleep: fn _ -> :ok end] ++
        extra

  defp item(rkey, text, record_extra \\ %{}, item_extra \\ %{}) do
    Map.merge(
      %{
        "post" => %{
          "uri" => "at://did:plc:abc/app.bsky.feed.post/#{rkey}",
          "author" => %{"did" => "did:plc:abc", "handle" => "alice.bsky.social"},
          "record" =>
            Map.merge(%{"text" => text, "createdAt" => "2026-11-08T09:00:00.000Z"}, record_extra)
        }
      },
      item_extra
    )
  end

  test "recent posts are fetched with no credentials and mapped to canonical posts (Recent posts fetched)" do
    Req.Test.stub(@stub, fn conn ->
      send(
        self(),
        {:request, conn.request_path, conn.query_string,
         Plug.Conn.get_req_header(conn, "authorization")}
      )

      Req.Test.json(conn, %{
        "feed" => [
          item("p1", "Deal today", %{
            "facets" => [
              %{
                "features" => [
                  %{"$type" => "app.bsky.richtext.facet#link", "uri" => "https://deals.example/a"}
                ]
              }
            ]
          }),
          item("p2", "Read this", %{
            "embed" => %{
              "$type" => "app.bsky.embed.external",
              "external" => %{"uri" => "https://news.example/b"}
            }
          }),
          # A repost of someone else's post is skipped.
          item("p3", "Not theirs", %{}, %{
            "reason" => %{"$type" => "app.bsky.feed.defs#reasonRepost"}
          })
        ]
      })
    end)

    assert {:ok, [p1, p2]} = Bluesky.fetch_posts("@alice.bsky.social", opts())

    assert %{
             id: "p1",
             handle: "alice.bsky.social",
             text: "Deal today",
             urls: ["https://deals.example/a"]
           } = p1

    assert p1.published_at == "2026-11-08T09:00:00.000Z"
    assert p2.urls == ["https://news.example/b"]

    assert_received {:request, "/xrpc/app.bsky.feed.getAuthorFeed", query, []}
    assert URI.decode_query(query)["actor"] == "alice.bsky.social"
  end

  test "a 429 backs off and retries, and gives up with an error (Rate limited)" do
    Req.Test.stub(@stub, fn conn -> conn |> Plug.Conn.put_status(429) |> Req.Test.json(%{}) end)

    assert {:error, {:rate_limited, 3}} =
             Bluesky.fetch_posts("alice.bsky.social", opts(max_retries: 2))
  end

  test "profiles resolve DIDs to handles" do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{
        "profiles" => [
          %{"did" => "did:plc:abc", "handle" => "alice.bsky.social", "displayName" => "Alice"}
        ]
      })
    end)

    assert {:ok, [%{did: "did:plc:abc", handle: "alice.bsky.social", display_name: "Alice"}]} =
             Bluesky.profiles(["did:plc:abc"], opts())
  end

  test "the checked-in seed corpus resolves for offline tests" do
    assert {:ok, path} = Dripstone.Test.Corpus.latest("bluesky")
    assert [first | _] = Dripstone.Test.Corpus.read!(path)
    assert first["source"] =~ "bluesky:"
    assert is_binary(first["fetched_at"])
  end
end
