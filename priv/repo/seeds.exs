# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Registration is closed (no public sign-up): analysts are seeded here and
# confirmed so they can log in immediately. Re-runs never reset passwords.

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

  user =
    if is_nil(user.hashed_password) do
      {:ok, {user, _}} =
        Accounts.update_user_password(user, %{password: "change-me-after-login!"})

      user
    else
      user
    end

  if is_nil(user.confirmed_at) do
    user |> User.confirm_changeset() |> Repo.update!()
  end
end
