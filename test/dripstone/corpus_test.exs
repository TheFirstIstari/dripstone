defmodule Dripstone.Test.CorpusTest do
  use ExUnit.Case, async: true

  alias Dripstone.Test.Corpus

  setup do
    dir = Path.join(System.tmp_dir!(), "corpus-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "x"))
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "latest/2 picks the newest dated corpus", %{dir: dir} do
    File.write!(Path.join(dir, "x/2026-11-01.jsonl"), "{}\n")
    File.write!(Path.join(dir, "x/2026-11-07.jsonl"), "{}\n")

    assert {:ok, path} = Corpus.latest("x", datasets_dir: dir)
    assert Path.basename(path) == "2026-11-07.jsonl"
  end

  test "latest/2 errors when no corpus exists", %{dir: dir} do
    assert {:error, _} = Corpus.latest("nope", datasets_dir: dir)
    assert {:error, _} = Corpus.latest("x", datasets_dir: dir)
  end

  test "read!/1 decodes one map per JSONL line", %{dir: dir} do
    path = Path.join(dir, "x/2026-11-01.jsonl")

    File.write!(path, ~s({"id":"x1","source":"x:@a"}\n{"id":"x2","source":"x:@a"}\n))

    assert [%{"id" => "x1"}, %{"id" => "x2"}] = Corpus.read!(path)
  end
end
