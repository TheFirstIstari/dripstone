defmodule Dripstone.ReleaseTest do
  use Dripstone.DataCase, async: false

  alias Dripstone.{Accounts, Release}

  test "seed_analysts is idempotent and never resets existing passwords" do
    System.put_env("ANALYST_EMAIL", "seedcheck@dripstone.dev")
    System.delete_env("ANALYST_EMAILS")
    System.put_env("ANALYST_PASSWORD", "supersecretpw123")

    on_exit(fn ->
      System.delete_env("ANALYST_EMAIL")
      System.delete_env("ANALYST_EMAILS")
      System.delete_env("ANALYST_PASSWORD")
    end)

    assert :ok = Release.seed_analysts()

    user = Accounts.get_user_by_email("seedcheck@dripstone.dev")
    assert user.confirmed_at
    assert Accounts.get_user_by_email_and_password("seedcheck@dripstone.dev", "supersecretpw123")

    assert :ok = Release.seed_analysts()

    rerun = Accounts.get_user_by_email("seedcheck@dripstone.dev")
    assert rerun.hashed_password == user.hashed_password
    assert Accounts.get_user_by_email_and_password("seedcheck@dripstone.dev", "supersecretpw123")
  end
end
