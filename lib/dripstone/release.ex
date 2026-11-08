defmodule Dripstone.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :dripstone

  def migrate do
    load_app()

    for repo <- repos() do
      _ = repo.__adapter__().storage_up(repo.config())
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Release-safe port of `priv/repo/seeds.exs` analyst logic (no Mix).
  Idempotent: never resets existing passwords; confirms users.
  """
  def seed_analysts do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _ ->
          for email <- analyst_emails() do
            user =
              case Dripstone.Accounts.get_user_by_email(email) do
                nil ->
                  {:ok, user} = Dripstone.Accounts.register_user(%{email: email})
                  user

                user ->
                  Dripstone.Repo.get!(Dripstone.Accounts.User, user.id)
              end

            if is_nil(user.hashed_password) do
              password = System.get_env("ANALYST_PASSWORD", "")

              if String.trim(password) == "" do
                raise "ANALYST_PASSWORD is missing or blank: set it in the environment and re-run (min 12 chars)"
              end

              case Dripstone.Accounts.update_user_password(user, %{password: password}) do
                {:ok, {user, _}} ->
                  user

                {:error, changeset} ->
                  raise "ANALYST_PASSWORD invalid: #{inspect(changeset.errors)} (min 12 chars)"
              end
            end

            user = Dripstone.Repo.get!(Dripstone.Accounts.User, user.id)

            if is_nil(user.confirmed_at) do
              user |> Dripstone.Accounts.User.confirm_changeset() |> Dripstone.Repo.update!()
            end

            IO.puts("Seeded analyst #{email} (password login ready).")
          end
        end)
    end

    :ok
  end

  defp analyst_emails do
    [
      System.get_env("ANALYST_EMAIL", "analyst@dripstone.dev")
      | String.split(System.get_env("ANALYST_EMAILS", ""), ",", trim: true)
    ]
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq_by(&String.downcase/1)
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
