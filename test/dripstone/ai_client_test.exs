defmodule Dripstone.AIClientTest do
  use ExUnit.Case, async: true

  test "falls back to mock reply when the AI host is unreachable" do
    old = System.get_env("INTERNAL_AI_URL")

    on_exit(fn ->
      if old,
        do: System.put_env("INTERNAL_AI_URL", old),
        else: System.delete_env("INTERNAL_AI_URL")
    end)

    System.put_env("INTERNAL_AI_URL", "http://127.0.0.1:9")

    assert {:ok, "[mock] hello"} = Dripstone.AIClient.complete("hello")
  end
end
