# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Registration is closed (no public sign-up): analysts are seeded here with NO
# password (password login impossible) and must use magic-link login for first
# access, then set a password via /users/settings. Re-runs never touch passwords.

alias Dripstone.Accounts
alias Dripstone.Accounts.User
alias Dripstone.Repo

emails =
  [
    System.get_env("ANALYST_EMAIL", "analyst@dripstone.dev")
    | String.split(System.get_env("ANALYST_EMAILS", ""), ",", trim: true)
  ]
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))
  |> Enum.uniq_by(&String.downcase/1)

for email <- emails do
  user =
    case Accounts.get_user_by_email(email) do
      nil ->
        {:ok, user} = Accounts.register_user(%{email: email})
        user

      user ->
        Repo.get!(User, user.id)
    end

  if is_nil(user.confirmed_at) do
    user |> User.confirm_changeset() |> Repo.update!()
  end

  Mix.shell().info("""
  Seeded analyst #{email} with no password. \
  Log in via the magic-link form on /users/log-in, then set a password in settings.
  """)
end
