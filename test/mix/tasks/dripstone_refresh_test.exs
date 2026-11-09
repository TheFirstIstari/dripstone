defmodule Mix.Tasks.Dripstone.RefreshTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Dripstone.Refresh

  @switches [platform: :string, handle: :string, all: :boolean, date: :string]

  test "positional platform is rewritten to --platform with flags preserved" do
    assert Refresh.forward_args(["x", "--handle", "@someone"]) == [
             "--platform",
             "x",
             "--handle",
             "@someone"
           ]
  end

  test "--platform flag passes through untouched" do
    args = ["--platform", "reddit", "--handle", "u/someone"]
    assert Refresh.forward_args(args) == args
  end

  test "--all passes through untouched" do
    args = ["--all", "--handle", "@someone"]
    assert Refresh.forward_args(args) == args
  end

  test "positional plus --platform/--all raises instead of silently winning" do
    assert_raise Mix.Error, fn -> Refresh.forward_args(["x", "--platform", "reddit"]) end
    assert_raise Mix.Error, fn -> Refresh.forward_args(["x", "--all"]) end
  end

  test "--date survives positional forwarding" do
    forwarded = Refresh.forward_args(["x", "--handle", "@someone", "--date", "2026-11-08"])

    assert {opts, _, _} = OptionParser.parse(forwarded, strict: @switches)
    assert opts[:platform] == "x"
    assert opts[:handle] == "@someone"
    assert opts[:date] == "2026-11-08"
  end
end
