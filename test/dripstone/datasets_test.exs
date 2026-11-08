defmodule Dripstone.DatasetsTest do
  use ExUnit.Case, async: true

  alias Dripstone.Datasets

  defmodule FlakyAdapter do
    @moduledoc false
    @behaviour Dripstone.Adapters

    @impl true
    def fetch_posts(handle, opts) do
      n = Process.get(:flaky_attempts, 0)
      Process.put(:flaky_attempts, n + 1)

      if n < Keyword.get(opts, :fail_times, 0) do
        {:error, {:http_status, 429}}
      else
        {:ok, [%{id: "1", handle: handle, text: "hi", urls: [], published_at: nil}]}
      end
    end
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "datasets-#{System.unique_integer([:positive])}")
    # Stale dirs can survive on shared runners across reboots (counter resets).
    File.rm_rf!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "refresh writes a dated corpus with fetched_at and source", %{dir: dir} do
    opts = [datasets_dir: dir, date: "2026-11-07", retry_sleep_ms: 0]

    assert {:ok, path} =
             Datasets.refresh(
               Dripstone.Adapters.StubX,
               "x",
               "@someone",
               Keyword.put(opts, :fixture_path, "test/fixtures/stub_x_posts.json")
             )

    assert path == Path.join([dir, "x", "2026-11-07.jsonl"])
    assert {:ok, lines} = Datasets.read_corpus("x", datasets_dir: dir)
    assert length(lines) == 4

    first = hd(lines)
    assert first["id"] == "x1"
    assert first["source"] == "x:@someone"
    assert %{"fetched_at" => fetched} = first
    assert {:ok, _, _} = DateTime.from_iso8601(fetched)
    assert is_binary(first["text"])
  end

  test "checked-in corpora load offline with post fields plus fetched_at and source" do
    assert {:ok, x} = Datasets.read_corpus("x")
    assert {:ok, reddit} = Datasets.read_corpus("reddit")
    assert length(x) > 0 and length(reddit) > 0

    for post <- x ++ reddit do
      assert is_binary(post["id"])
      assert is_binary(post["text"])
      assert is_list(post["urls"])
      assert is_binary(post["source"])
      assert {:ok, _, _} = DateTime.from_iso8601(post["fetched_at"])
    end
  end

  test "latest_corpus picks the newest date and errors when absent", %{dir: dir} do
    assert {:error, :no_corpus} = Datasets.latest_corpus("x", datasets_dir: dir)

    Datasets.write_corpus("x", "h", [], datasets_dir: dir, date: "2026-11-01")
    Datasets.write_corpus("x", "h", [], datasets_dir: dir, date: "2026-11-05")

    assert {:ok, path} = Datasets.latest_corpus("x", datasets_dir: dir)
    assert Path.basename(path) == "2026-11-05.jsonl"
  end

  test "refresh backs off and retries on 429, then records", %{dir: dir} do
    opts = [datasets_dir: dir, date: "2026-11-07", fail_times: 2, retry_sleep_ms: 0]

    assert {:ok, _} = Datasets.refresh(FlakyAdapter, "x", "@someone", opts)
    assert Process.get(:flaky_attempts) == 3
    assert {:ok, [post]} = Datasets.read_corpus("x", datasets_dir: dir)
    assert post["source"] == "x:@someone"
  end

  test "refresh gives up after max retries", %{dir: dir} do
    opts = [datasets_dir: dir, fail_times: 9, max_retries: 2, retry_sleep_ms: 0]

    assert {:error, {:http_status, 429}} = Datasets.refresh(FlakyAdapter, "x", "h", opts)
    assert Process.get(:flaky_attempts) == 3
  end

  test "refresh propagates non-rate-limit errors without retrying", %{dir: dir} do
    opts = [datasets_dir: dir, fixture_path: "/nonexistent.json"]

    assert {:error, _} = Datasets.refresh(Dripstone.Adapters.StubX, "x", "h", opts)
  end

  test "read_corpus skips one corrupt line and reads the rest", %{dir: dir} do
    File.mkdir_p!(Path.join(dir, "x"))

    File.write!(
      Path.join([dir, "x", "2026-11-07.jsonl"]),
      ~s({"id":"x1"}\nnot json\n{"id":"x2"}\n)
    )

    assert {:ok, lines} = Datasets.read_corpus("x", datasets_dir: dir)
    assert [%{"id" => "x1"}, %{"id" => "x2"}] = lines
  end

  test "write_corpus with empty posts reads back empty", %{dir: dir} do
    assert {:ok, path} =
             Datasets.write_corpus("x", "h", [], datasets_dir: dir, date: "2026-11-07")

    assert File.read!(path) == ""
    assert {:ok, []} = Datasets.read_corpus("x", datasets_dir: dir)
  end

  test "write_corpus rejects date traversal and corpus_path raises", %{dir: dir} do
    evil = Path.join(dir, "evil.jsonl")
    File.rm(evil)

    assert {:error, :invalid_date} =
             Datasets.write_corpus("x", "h", [], datasets_dir: dir, date: "../../evil")

    assert_raise ArgumentError, fn -> Datasets.corpus_path("x", "../../evil") end
    refute File.exists?(evil)
  end

  test "latest_corpus ignores stray non-dated jsonl files", %{dir: dir} do
    Datasets.write_corpus("x", "h", [], datasets_dir: dir, date: "2026-11-01")
    File.write!(Path.join([dir, "x", "notes.jsonl"]), ~s({"id":"stray"}\n))

    assert {:ok, path} = Datasets.latest_corpus("x", datasets_dir: dir)
    assert Path.basename(path) == "2026-11-01.jsonl"
    assert {:ok, []} = Datasets.read_corpus("x", datasets_dir: dir)
  end

  test "platform traversal is rejected", %{dir: dir} do
    assert_raise ArgumentError, fn -> Datasets.corpus_path("../../evil", "2026-11-07") end
    assert_raise ArgumentError, fn -> Datasets.latest_corpus("*", datasets_dir: dir) end

    assert {:error, :invalid_platform} =
             Datasets.write_corpus("../../evil", "h", [], datasets_dir: dir, date: "2026-11-07")

    refute File.exists?(Path.join(dir, "evil.jsonl"))
  end
end
