defmodule Dripstone.AIClientTest do
  use ExUnit.Case, async: true

  test "falls back to mock reply when the AI host is unreachable" do
    System.put_env("INTERNAL_AI_URL", "http://127.0.0.1:9")

    assert {:ok, "[mock] hello"} = Dripstone.AIClient.complete("hello")
  after
    System.delete_env("INTERNAL_AI_URL")
  end
end
