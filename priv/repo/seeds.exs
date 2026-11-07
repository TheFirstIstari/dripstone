# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Registration is closed (no public sign-up): analysts are seeded here with an
# email+password login (spec "Analyst login"). The initial password comes from
# ANALYST_PASSWORD and is only set for analysts created without one; re-runs
# never reset existing passwords.

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

  if is_nil(user.hashed_password) do
    password = System.get_env("ANALYST_PASSWORD", "")

    if String.trim(password) == "" do
      Mix.raise(
        "ANALYST_PASSWORD is missing or blank: set it in the environment and re-run seeds (min 12 chars)"
      )
    end

    case Accounts.update_user_password(user, %{password: password}) do
      {:ok, {user, _}} ->
        user

      {:error, changeset} ->
        Mix.raise("ANALYST_PASSWORD invalid: #{inspect(changeset.errors)} (min 12 chars)")
    end
  end

  user = Repo.get!(User, user.id)

  if is_nil(user.confirmed_at) do
    user |> User.confirm_changeset() |> Repo.update!()
  end

  Mix.shell().info("Seeded analyst #{email} (password login ready).")
end
