defmodule DripstoneWeb.UserSessionController do
  use DripstoneWeb, :controller

  alias Dripstone.Accounts
  alias DripstoneWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "User confirmed successfully.")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info)
       when is_binary(token) do
    # verify_magic_link_token_query returns :error (not {:ok, _}) for
    # non-base64 tokens, which login_user_by_magic_link/1 match-asserts on;
    # screen here to stay on the invalid-link branch instead of MatchError.
    case Base.url_decode64(token, padding: false) do
      :error ->
        invalid_link(conn)

      {:ok, _} ->
        case Accounts.login_user_by_magic_link(token) do
          {:ok, {user, tokens_to_disconnect}} ->
            UserAuth.disconnect_sessions(tokens_to_disconnect)
            DripstoneWeb.LoginThrottle.reset(throttle_key(conn, user.email))

            conn
            |> put_flash(:info, info)
            |> UserAuth.log_in_user(user, user_params)

          _ ->
            invalid_link(conn)
        end
    end
  end

  # Non-binary token never verifies; same branch as an invalid link.
  defp create(conn, %{"user" => %{"token" => _}}, _info), do: invalid_link(conn)

  defp create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}, info)
       when is_binary(email) and is_binary(password) do
    key = throttle_key(conn, email)

    # Single atomic check-and-record before verification: concurrent
    # guesses share one budget instead of all passing a separate allowed? first.
    case DripstoneWeb.LoginThrottle.check_and_record(key) do
      :throttled ->
        conn
        |> put_flash(:error, "Too many login attempts. Try again in a minute.")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log-in")

      :ok ->
        if user = Accounts.get_user_by_email_and_password(email, password) do
          DripstoneWeb.LoginThrottle.reset(key)

          conn
          |> put_flash(:info, info)
          |> UserAuth.log_in_user(user, user_params)
        else
          # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
          conn
          |> put_flash(:error, "Invalid email or password")
          |> put_flash(:email, String.slice(email, 0, 160))
          |> redirect(to: ~p"/users/log-in")
        end
    end
  end

  # Missing keys or non-binary email/password: same branch as bad credentials.
  defp create(conn, _params, _info), do: invalid_credentials(conn)

  defp invalid_link(conn) do
    conn
    |> put_flash(:error, "The link is invalid or it has expired.")
    |> redirect(to: ~p"/users/log-in")
  end

  defp invalid_credentials(conn) do
    conn
    |> put_flash(:error, "Invalid email or password")
    |> redirect(to: ~p"/users/log-in")
  end

  defp throttle_key(conn, email) do
    DripstoneWeb.LoginThrottle.key(conn.remote_ip, email)
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user

    if Accounts.sudo_mode?(user) do
      case Accounts.update_user_password(user, user_params) do
        {:ok, {_user, expired_tokens}} ->
          # disconnect all existing LiveViews with old sessions
          UserAuth.disconnect_sessions(expired_tokens)

          conn
          |> put_session(:user_return_to, ~p"/users/settings")
          |> create(params, "Password updated successfully!")

        {:error, _changeset} ->
          conn
          |> put_flash(:error, "Password update failed. Check the requirements and try again.")
          |> redirect(to: ~p"/users/settings")
      end
    else
      conn
      |> put_flash(:error, "You must re-authenticate to access this page.")
      |> redirect(to: ~p"/users/log-in")
    end
  end

  # No "user" params at all: same failure branch as a rejected change.
  def update_password(conn, _params) do
    conn
    |> put_flash(:error, "Password update failed. Check the requirements and try again.")
    |> redirect(to: ~p"/users/settings")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
