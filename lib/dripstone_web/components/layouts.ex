defmodule DripstoneWeb.Layouts do
  @moduledoc """
  Layouts: the root HTML skeleton (`root.html.heex`) and the Dripstone app shell
  (`app/1`): sidebar navigation with the open-alert badge, a drawer on narrow
  screens, a top bar with account search and the theme toggle, flash messages and
  live alert toasts.
  """
  use DripstoneWeb, :html

  # Embed all files in layouts/* within this module.
  embed_templates "layouts/*"

  @sections [
    {:overview, "Overview", "/", "hero-squares-2x2"},
    {:alerts, "Alerts", "/alerts", "hero-bell-alert"},
    {:networks, "Networks", "/networks", "hero-share"},
    {:accounts, "Accounts", "/accounts", "hero-user-group"},
    {:feeds, "Feeds", "/feeds", "hero-signal"}
  ]

  @doc """
  Renders the app shell around a page.

  `nav` comes from `DripstoneWeb.Nav` (`@nav` in every tracker LiveView): the active
  section, the open alert count and the live toasts.

  ## Examples

      <Layouts.app flash={@flash} nav={@nav}>
        <h1>Content</h1>
      </Layouts.app>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :nav, :map,
    default: %{active: nil, open_alerts: 0, toasts: []},
    doc: "navigation state from DripstoneWeb.Nav"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-canvas text-ink">
      <aside
        id="sidebar"
        class="fixed inset-y-0 left-0 z-30 hidden w-60 flex-col border-r border-line bg-surface lg:flex"
      >
        <.sidebar nav={@nav} prefix="nav" source_id="data-source" />
      </aside>

      <div
        id="nav-drawer"
        class="fixed inset-0 z-40 hidden lg:hidden"
        role="dialog"
        aria-modal="true"
        aria-label="Navigation"
      >
        <div
          class="absolute inset-0 bg-ink/40 backdrop-blur-[2px]"
          phx-click={close_drawer()}
          aria-hidden="true"
        >
        </div>
        <div
          id="nav-drawer-panel"
          class="absolute inset-y-0 left-0 flex w-64 max-w-[85vw] flex-col border-r border-line bg-surface shadow-pop"
          phx-click-away={close_drawer()}
          phx-window-keydown={close_drawer()}
          phx-key="escape"
        >
          <button
            id="close-nav"
            type="button"
            phx-click={close_drawer()}
            class="absolute top-3.5 right-3 rounded p-1 text-ink-faint hover:text-ink cursor-pointer"
            aria-label="Close navigation"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
          <.sidebar nav={@nav} prefix="drawer-nav" source_id="drawer-data-source" />
        </div>
      </div>

      <div class="lg:pl-60">
        <header
          id="topbar"
          class="sticky top-0 z-20 flex h-14 items-center gap-3 border-b border-line bg-canvas/85 px-4 backdrop-blur sm:px-6 lg:px-8"
        >
          <button
            id="open-nav"
            type="button"
            phx-click={open_drawer()}
            class="-ml-1 rounded-lg p-1.5 text-ink-muted hover:bg-surface-raised hover:text-ink lg:hidden cursor-pointer"
            aria-label="Open navigation"
            aria-controls="nav-drawer"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>

          <.form
            for={to_form(%{"q" => ""}, as: :search)}
            id="global-search"
            phx-submit="global_search"
            role="search"
            class="relative w-full max-w-md"
          >
            <.icon
              name="hero-magnifying-glass"
              class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-ink-faint"
            />
            <label for="global-search-q" class="sr-only">Search accounts</label>
            <input
              id="global-search-q"
              type="search"
              name="q"
              value=""
              autocomplete="off"
              placeholder="Search accounts by handle or name…"
              class="block h-9 w-full rounded-lg border border-line bg-surface pr-3 pl-9 text-sm text-ink placeholder:text-ink-faint shadow-card transition-colors hover:border-line-strong focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/25"
            />
          </.form>

          <div class="ml-auto flex items-center gap-2 sm:gap-3">
            <.user_menu current_scope={@current_scope} />
            <.theme_toggle />
          </div>
        </header>

        <main id="main" class="px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
          <div class="mx-auto max-w-7xl">
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>

      <.flash_group flash={@flash} />
      <.toast_stack toasts={@nav.toasts} />
    </div>
    """
  end

  attr :current_scope, :map, default: nil

  # Signed-in analyst (email, Settings, Log out) or Log in / Register links.
  defp user_menu(assigns) do
    ~H"""
    <nav id="user-menu" class="flex items-center gap-1 text-sm" aria-label="Account">
      <%= if @current_scope && @current_scope.user do %>
        <span
          id="user-email"
          class="hidden max-w-48 truncate px-2 text-ink-muted md:inline"
          title={@current_scope.user.email}
        >
          {@current_scope.user.email}
        </span>
        <.link
          href={~p"/users/settings"}
          class="rounded-lg px-2 py-1.5 text-ink-muted hover:bg-surface-raised hover:text-ink"
        >
          Settings
        </.link>
        <.link
          href={~p"/users/log-out"}
          method="delete"
          class="rounded-lg px-2 py-1.5 text-ink-muted hover:bg-surface-raised hover:text-ink"
        >
          Log out
        </.link>
      <% else %>
        <.link
          href={~p"/users/register"}
          class="hidden rounded-lg px-2 py-1.5 text-ink-muted hover:bg-surface-raised hover:text-ink sm:inline"
        >
          Register
        </.link>
        <.link
          href={~p"/users/log-in"}
          class="rounded-lg bg-accent px-3 py-1.5 font-medium text-accent-ink hover:bg-accent-strong"
        >
          Log in
        </.link>
      <% end %>
    </nav>
    """
  end

  attr :nav, :map, required: true
  attr :prefix, :string, required: true
  attr :source_id, :string, required: true

  defp sidebar(assigns) do
    assigns = assign(assigns, :sections, @sections)

    ~H"""
    <.link navigate="/" class="flex h-14 items-center gap-2.5 border-b border-line px-5">
      <span class="flex size-7 items-center justify-center rounded-lg bg-accent text-accent-ink">
        <svg viewBox="0 0 24 24" class="size-4" fill="currentColor" aria-hidden="true">
          <path d="M4 3h16l-2.2 4.4H6.2zM7.3 9.4h9.4L15 13H9zM10 15h4l-1 3.2h-2zM11.2 20h1.6l-.8 1.6z" />
        </svg>
      </span>
      <span class="text-[15px] font-semibold tracking-tight text-ink">Dripstone</span>
    </.link>

    <nav class="flex-1 overflow-y-auto px-3 py-4" aria-label="Primary">
      <ul class="space-y-0.5">
        <li :for={{key, label, path, icon} <- @sections}>
          <.link
            id={"#{@prefix}-#{key}"}
            navigate={path}
            aria-current={if(@nav.active == key, do: "page")}
            class={[
              "group flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
              if(@nav.active == key,
                do: "bg-accent-soft text-accent-strong",
                else: "text-ink-muted hover:bg-surface-raised hover:text-ink"
              )
            ]}
          >
            <.icon
              name={icon}
              class={[
                "size-5 shrink-0",
                if(@nav.active == key,
                  do: "text-accent-strong",
                  else: "text-ink-faint group-hover:text-ink-muted"
                )
              ]}
            />
            <span class="flex-1">{label}</span>
            <span
              :if={key == :alerts and @nav.open_alerts > 0}
              id={"#{@prefix}-alerts-badge"}
              class="min-w-5 rounded-full bg-sev-high px-1.5 py-0.5 text-center text-[11px] font-semibold tabular-nums text-white"
              aria-label={"#{@nav.open_alerts} open alerts"}
            >
              {@nav.open_alerts}
            </span>
          </.link>
        </li>
      </ul>
    </nav>

    <div class="border-t border-line px-5 py-4">
      <p id={@source_id} class="flex items-center gap-2 text-xs font-medium text-ink-muted">
        <span class="size-2 rounded-full bg-status-suspected" aria-hidden="true"></span> Sample data
      </p>
      <p class="mt-1 text-xs text-ink-faint">Resets when the app restarts.</p>
    </div>
    """
  end

  defp open_drawer(js \\ %JS{}) do
    js
    |> JS.show(to: "#nav-drawer")
    |> JS.show(
      to: "#nav-drawer-panel",
      time: 200,
      transition:
        {"transition-transform ease-out duration-200", "-translate-x-full", "translate-x-0"}
    )
    |> JS.focus_first(to: "#nav-drawer-panel")
  end

  defp close_drawer(js \\ %JS{}) do
    js
    |> JS.hide(
      to: "#nav-drawer-panel",
      time: 150,
      transition:
        {"transition-transform ease-in duration-150", "translate-x-0", "-translate-x-full"}
    )
    |> JS.hide(to: "#nav-drawer", time: 150)
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Light / dark / system theme toggle. The choice is stored in localStorage and
  applied before first paint by the script in `root.html.heex`.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div
      id="theme-toggle"
      class="relative flex items-center rounded-full border border-line bg-surface-raised p-0.5"
      role="group"
      aria-label="Theme"
    >
      <div class="absolute top-0.5 left-0.5 h-7 w-7 rounded-full bg-surface shadow-card transition-[left] duration-200 [[data-theme=light]_&]:left-[1.875rem] [[data-theme=dark]_&]:left-[3.625rem] [[data-theme-source=system]_&]:!left-0.5" />
      <button
        :for={
          {theme, icon, label} <- [
            {"system", "hero-computer-desktop-micro", "System theme"},
            {"light", "hero-sun-micro", "Light theme"},
            {"dark", "hero-moon-micro", "Dark theme"}
          ]
        }
        type="button"
        class="relative flex size-7 items-center justify-center rounded-full text-ink-faint hover:text-ink cursor-pointer"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme={theme}
        aria-label={label}
      >
        <.icon name={icon} class="size-4" />
      </button>
    </div>
    """
  end
end
