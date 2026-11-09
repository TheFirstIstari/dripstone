defmodule DripstoneWeb.Router do
  use DripstoneWeb, :router

  import DripstoneWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DripstoneWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Other scopes may use custom stacks.
  # scope "/api", DripstoneWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:dripstone, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DripstoneWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  # Everything an analyst uses requires login (project spec, "Analyst login").
  # The tracker screens share this live_session with the account settings pages,
  # so moving between them is a live navigation. DripstoneWeb.Nav provides the
  # shell's navigation state; it runs after the login check.
  scope "/", DripstoneWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{DripstoneWeb.UserAuth, :require_authenticated}, DripstoneWeb.Nav] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      live "/alerts", AlertLive.Index
      live "/alerts/:id", AlertLive.Show
      live "/networks", NetworkLive.Index
      live "/networks/:id", NetworkLive.Show
      live "/accounts", AccountLive.Index
      live "/accounts/:id", AccountLive.Show
      live "/digest", DigestLive
      live "/feeds", FeedLive.Index
    end

    post "/users/update-password", UserSessionController, :update_password
    post "/mode", ModeController, :update
  end

  # The root is public so deploy checks see a 200: logged-out visitors get a
  # landing page, logged-in analysts get the overview dashboard (see
<<<<<<< Updated upstream
  # OverviewLive). Everything else an analyst uses still requires login.
=======
  # OverviewLive). Everything else an analyst uses still requires login
  # (project spec, "Analyst login").
>>>>>>> Stashed changes
  scope "/", DripstoneWeb do
    pipe_through [:browser]

    live_session :root,
      on_mount: [{DripstoneWeb.UserAuth, :mount_current_scope}, DripstoneWeb.Nav] do
      live "/", OverviewLive
<<<<<<< Updated upstream
    end

    live_session :current_user,
      on_mount: [{DripstoneWeb.UserAuth, :mount_current_scope}] do
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
=======
>>>>>>> Stashed changes
    end

    post "/users/update-password", UserSessionController, :update_password
  end

end
