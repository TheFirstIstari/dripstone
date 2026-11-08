defmodule Dripstone.Test.HttpGuard do
  @moduledoc """
  Zero-network CI guard: any `Req` call without an explicit `:plug` (e.g. a
  `Req.Test` stub) raises instead of touching the network. Attached once from
  `test_helper.exs` via `Req.default_options/1`; explicit `:plug` opts win, so
  stubbed tests are unaffected.
  """

  def attach do
    Req.default_options(plug: &deny/1)
  end

  defp deny(conn) do
    raise "network disabled in tests: #{conn.method} #{conn.host}#{conn.request_path} " <>
            "— pass plug: {Req.Test, stub} or read a fixture instead"
  end
end
