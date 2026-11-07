defmodule DripstoneWeb.TrackerComponents do
  @moduledoc """
  Dripstone's domain components: badges, page furniture, charts, toasts, history and
  the network graph. Imported everywhere through `DripstoneWeb.html_helpers/0`.

  Accessibility rules every component here follows: status-like values (severity,
  risk, status, strength) always show a text label next to their color, and charts
  always render a text summary plus an `aria-label`.
  """
  use Phoenix.Component
  use Gettext, backend: DripstoneWeb.Gettext

  import DripstoneWeb.CoreComponents, only: [icon: 1]

  alias Dripstone.Feeds
  alias Dripstone.Tracker.Link

  ## Badges

  @severity %{
    low: {"Low", "text-sev-low bg-sev-low/10 ring-sev-low/25"},
    medium: {"Medium", "text-sev-medium bg-sev-medium/10 ring-sev-medium/30"},
    high: {"High", "text-sev-high bg-sev-high/10 ring-sev-high/30"}
  }

  @doc "Alert severity, as a colored badge that always includes the text label."
  attr :severity, :atom, required: true, values: [:low, :medium, :high]
  attr :class, :any, default: nil

  def severity_badge(assigns) do
    {label, tone} = Map.fetch!(@severity, assigns.severity)
    assigns = assign(assigns, label: label, tone: tone)

    ~H"""
    <span class={[badge_class(), @tone, @class]} data-severity={@severity}>
      <.severity_glyph severity={@severity} />{@label}
    </span>
    """
  end

  attr :severity, :atom, required: true

  defp severity_glyph(%{severity: :high} = assigns),
    do: ~H|<.icon name="hero-exclamation-triangle-mini" class="size-3.5" />|

  defp severity_glyph(%{severity: :medium} = assigns),
    do: ~H|<span class="size-2 rotate-45 rounded-[1px] bg-current" aria-hidden="true"></span>|

  defp severity_glyph(assigns),
    do: ~H|<span class="size-2 rounded-full bg-current" aria-hidden="true"></span>|

  @risk %{
    low: {"Low", "text-risk-low bg-risk-low/10 ring-risk-low/25"},
    medium: {"Medium", "text-risk-medium bg-risk-medium/10 ring-risk-medium/30"},
    high: {"High", "text-risk-high bg-risk-high/10 ring-risk-high/30"}
  }

  @doc "An account's risk: level label and score together, e.g. `High 91`."
  attr :score, :integer, required: true
  attr :class, :any, default: nil

  def risk_badge(assigns) do
    level = Dripstone.Tracker.risk_level(assigns.score)
    {label, tone} = Map.fetch!(@risk, level)
    assigns = assign(assigns, label: label, tone: tone, level: level)

    ~H"""
    <span class={[badge_class(), @tone, "tabular-nums", @class]} data-risk={@level}>
      <span class="size-2 rounded-full bg-current" aria-hidden="true"></span>{@label}
      <span class="font-semibold">{@score}</span>
    </span>
    """
  end

  @status %{
    open: {"Open", "text-status-open"},
    suspected: {"Suspected", "text-status-suspected"},
    confirmed: {"Confirmed", "text-status-confirmed"},
    dismissed: {"Dismissed", "text-status-dismissed"},
    healthy: {"Healthy", "text-status-healthy"},
    degraded: {"Degraded", "text-status-degraded"},
    down: {"Down", "text-status-down"},
    not_connected: {"Not connected", "text-status-dismissed"}
  }

  @doc "Status of an alert, network or feed, as a dot plus its text label."
  attr :status, :atom, required: true
  attr :class, :any, default: nil

  def status_pill(assigns) do
    {label, tone} = Map.fetch!(@status, assigns.status)
    assigns = assign(assigns, label: label, tone: tone)

    ~H"""
    <span
      class={["inline-flex items-center gap-1.5 text-xs font-medium text-ink", @class]}
      data-status={@status}
    >
      <span class={["size-2 rounded-full bg-current", @tone]} aria-hidden="true"></span>{@label}
    </span>
    """
  end

  @strength %{
    weak: {"Weak", "text-strength-weak bg-strength-weak/10 ring-strength-weak/25", 1},
    moderate:
      {"Moderate", "text-strength-moderate bg-strength-moderate/10 ring-strength-moderate/25", 2},
    strong: {"Strong", "text-strength-strong bg-strength-strong/10 ring-strength-strong/30", 3}
  }

  @doc "Evidence or link strength: a three-step meter plus its text label."
  attr :strength, :atom, required: true, values: [:weak, :moderate, :strong]
  attr :class, :any, default: nil

  def strength_badge(assigns) do
    {label, tone, bars} = Map.fetch!(@strength, assigns.strength)
    assigns = assign(assigns, label: label, tone: tone, bars: bars)

    ~H"""
    <span class={[badge_class(), @tone, @class]} data-strength={@strength}>
      <span class="flex items-end gap-px" aria-hidden="true">
        <span
          :for={n <- 1..3}
          class={["w-0.5 rounded-full bg-current", n > @bars && "opacity-25"]}
          style={"height: #{4 + n * 2}px"}
        ></span>
      </span>
      {@label}
    </span>
    """
  end

  @doc "A platform name from the feed registry; unknown feed ids show as a plain label."
  attr :feed_id, :string, required: true
  attr :class, :any, default: nil

  def platform_badge(assigns) do
    assigns = assign(assigns, :name, feed_name(assigns.feed_id))

    ~H"""
    <span class={[
      "inline-flex items-center rounded-md bg-surface-raised px-1.5 py-0.5 text-xs font-medium text-ink-muted ring-1 ring-line ring-inset",
      @class
    ]}>
      {@name}
    </span>
    """
  end

  @doc "Display name for a feed id, falling back to the id itself."
  def feed_name(feed_id) do
    case Feeds.get(feed_id) do
      nil -> feed_id
      feed -> feed.name()
    end
  end

  @doc "A network tag, optionally removable."
  attr :tag, :string, required: true
  attr :id, :string, default: nil
  attr :remove, :any, default: nil, doc: "phx-click for the remove button (event or JS)"
  attr :patch, :string, default: nil, doc: "makes the tag a link (e.g. to a filtered list)"

  def tag_chip(assigns) do
    ~H"""
    <span
      id={@id}
      class="inline-flex items-center gap-1 rounded-full bg-accent-soft px-2 py-0.5 text-xs font-medium text-accent-strong"
    >
      <.link :if={@patch} patch={@patch} class="hover:underline">#{@tag}</.link>
      <span :if={!@patch}>#{@tag}</span>
      <button
        :if={@remove}
        type="button"
        phx-click={@remove}
        phx-value-tag={@tag}
        class="-mr-0.5 rounded-full p-0.5 hover:bg-accent/15 cursor-pointer"
        aria-label={"Remove tag #{@tag}"}
      >
        <.icon name="hero-x-mark-mini" class="size-3" />
      </button>
    </span>
    """
  end

  @doc "Label for text written by the AI model, with when it was generated."
  attr :generated_at, DateTime, default: nil
  attr :class, :any, default: nil

  def ai_label(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1 text-xs font-medium text-strength-strong",
        @class
      ]}
      data-ai-label
    >
      <.icon name="hero-sparkles-mini" class="size-3.5" /> AI-generated
      <span :if={@generated_at} class="font-normal text-ink-faint">
        · <.relative_time at={@generated_at} />
      </span>
    </span>
    """
  end

  defp badge_class,
    do:
      "inline-flex items-center gap-1.5 rounded-md px-1.5 py-0.5 text-xs font-medium ring-1 ring-inset whitespace-nowrap"

  ## Time

  @doc """
  A relative time like `2h ago`, with the exact UTC time on hover. `now` defaults to
  the current time.
  """
  attr :at, DateTime, required: true
  attr :now, DateTime, default: nil
  attr :class, :any, default: nil

  def relative_time(assigns) do
    assigns = assign(assigns, :text, ago(assigns.at, assigns.now || DateTime.utc_now()))

    ~H"""
    <time
      datetime={DateTime.to_iso8601(@at)}
      title={Calendar.strftime(@at, "%Y-%m-%d %H:%M UTC")}
      class={["tabular-nums", @class]}
    >
      {@text}
    </time>
    """
  end

  @doc "Formats the time between `at` and `now`, e.g. `just now`, `5m ago`, `3d ago`."
  @spec ago(DateTime.t(), DateTime.t()) :: String.t()
  def ago(at, now) do
    seconds = max(DateTime.diff(now, at), 0)

    cond do
      seconds < 45 -> "just now"
      seconds < 3_600 -> "#{max(div(seconds, 60), 1)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3_600)}h ago"
      seconds < 30 * 86_400 -> "#{div(seconds, 86_400)}d ago"
      true -> Calendar.strftime(at, "%b %-d, %Y")
    end
  end

  ## Page furniture

  @doc "Page title block with optional back link, subtitle and actions."
  attr :title, :string, required: true
  attr :back, :string, default: nil, doc: "path for the back link"
  attr :back_label, :string, default: nil
  slot :subtitle
  slot :meta
  slot :actions

  def page_header(assigns) do
    ~H"""
    <header class="mb-6">
      <.link
        :if={@back}
        navigate={@back}
        class="mb-3 inline-flex items-center gap-1 text-sm text-ink-muted hover:text-ink"
      >
        <.icon name="hero-arrow-left-mini" class="size-4" />{@back_label}
      </.link>
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div class="min-w-0">
          <h1 id="page-title" class="text-xl font-semibold tracking-tight text-ink sm:text-2xl">
            {@title}
          </h1>
          <p :if={@subtitle != []} class="mt-1 text-sm text-ink-muted">{render_slot(@subtitle)}</p>
          <div
            :if={@meta != []}
            class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1.5 text-sm text-ink-muted"
          >
            {render_slot(@meta)}
          </div>
        </div>
        <div :if={@actions != []} class="flex flex-wrap items-center gap-2">
          {render_slot(@actions)}
        </div>
      </div>
    </header>
    """
  end

  @doc "A bordered card section with an optional title and header actions."
  attr :id, :string, default: nil
  attr :title, :string, default: nil
  attr :class, :any, default: nil
  attr :padded, :boolean, default: true
  slot :header_actions
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section
      id={@id}
      class={["rounded-card border border-line bg-surface shadow-card", @class]}
    >
      <div
        :if={@title || @header_actions != []}
        class="flex items-center justify-between gap-3 border-b border-line px-4 py-3"
      >
        <h2 :if={@title} class="text-sm font-semibold text-ink">{@title}</h2>
        <div :if={@header_actions != []} class="flex items-center gap-2 text-sm">
          {render_slot(@header_actions)}
        </div>
      </div>
      <div class={@padded && "p-4"}>{render_slot(@inner_block)}</div>
    </section>
    """
  end

  @doc "A headline number that links to the matching filtered screen."
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :navigate, :string, required: true
  attr :tone, :atom, default: :neutral, values: [:neutral, :alert]

  def stat_tile(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class="group block rounded-card border border-line bg-surface p-4 shadow-card transition hover:-translate-y-0.5 hover:border-line-strong hover:shadow-pop"
    >
      <p class="text-xs font-medium uppercase tracking-wide text-ink-faint">{@label}</p>
      <p class={[
        "mt-2 text-3xl font-semibold tabular-nums tracking-tight",
        if(@tone == :alert, do: "text-sev-high", else: "text-ink")
      ]}>
        {format_number(@value)}
      </p>
      <span class="mt-2 inline-flex items-center gap-1 text-xs text-ink-muted group-hover:text-accent">
        View
        <.icon
          name="hero-arrow-right-mini"
          class="size-3.5 transition-transform group-hover:translate-x-0.5"
        />
      </span>
    </.link>
    """
  end

  @doc "Formats integers with thousands separators (1284 -> 1,284)."
  def format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  def format_number(other), do: to_string(other)

  @doc "An explanatory empty state for a list, table or chart with nothing to show."
  attr :id, :string, default: nil
  attr :icon, :string, default: "hero-inbox"
  attr :title, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block
  slot :actions

  def empty_state(assigns) do
    ~H"""
    <div id={@id} class={["flex flex-col items-center px-6 py-10 text-center", @class]} data-empty>
      <span class="flex size-10 items-center justify-center rounded-full bg-surface-raised text-ink-faint">
        <.icon name={@icon} class="size-5" />
      </span>
      <p class="mt-3 text-sm font-medium text-ink">{@title}</p>
      <p :if={@inner_block != []} class="mt-1 max-w-sm text-sm text-ink-muted">
        {render_slot(@inner_block)}
      </p>
      <div :if={@actions != []} class="mt-4 flex gap-2">{render_slot(@actions)}</div>
    </div>
    """
  end

  @doc "Not-found state for a detail page, shown inside the app shell with a way back."
  attr :id, :string, default: "not-found"
  attr :title, :string, required: true
  attr :back, :string, required: true
  attr :back_label, :string, required: true

  def not_found(assigns) do
    ~H"""
    <div
      id={@id}
      class="mx-auto mt-12 max-w-md rounded-card border border-line bg-surface p-8 text-center shadow-card"
    >
      <span class="mx-auto flex size-12 items-center justify-center rounded-full bg-surface-raised text-ink-faint">
        <.icon name="hero-magnifying-glass" class="size-6" />
      </span>
      <h1 class="mt-4 text-lg font-semibold text-ink">{@title}</h1>
      <p class="mt-1 text-sm text-ink-muted">
        It may have been merged, removed, or the link is wrong.
      </p>
      <.link
        id={"#{@id}-back"}
        navigate={@back}
        class="mt-5 inline-flex items-center gap-1 text-sm font-medium text-accent hover:underline"
      >
        <.icon name="hero-arrow-left-mini" class="size-4" />{@back_label}
      </.link>
    </div>
    """
  end

  @doc """
  Filter row for a list screen. Wraps a `<.form>` bound to `for`, sends `phx-change`,
  and shows a Clear link when `clear` is a path.
  """
  attr :id, :string, required: true
  attr :for, :any, required: true
  attr :change, :string, default: "filter"
  attr :clear, :string, default: nil
  slot :inner_block, required: true

  def filter_bar(assigns) do
    ~H"""
    <.form
      for={@for}
      id={@id}
      phx-change={@change}
      phx-submit={@change}
      class="flex flex-wrap items-end gap-3 border-b border-line px-4 py-3 [&_.mb-2]:mb-0"
    >
      {render_slot(@inner_block)}
      <.link
        :if={@clear}
        patch={@clear}
        id={"#{@id}-clear"}
        class="mb-2 ml-auto text-sm text-ink-muted hover:text-ink"
      >
        Clear filters
      </.link>
    </.form>
    """
  end

  @doc "Previous/next pagination. `path` is a function from page number to a path."
  attr :id, :string, required: true
  attr :page, :integer, required: true
  attr :pages, :integer, required: true
  attr :path, :any, required: true

  def pager(assigns) do
    ~H"""
    <nav
      :if={@pages > 1}
      id={@id}
      class="flex items-center justify-end gap-3 border-t border-line px-4 py-3 text-sm"
      aria-label="Pagination"
    >
      <.link
        :if={@page > 1}
        id={"#{@id}-prev"}
        patch={@path.(@page - 1)}
        class="inline-flex items-center gap-1 text-ink-muted hover:text-ink"
      >
        <.icon name="hero-chevron-left-mini" /> Prev
      </.link>
      <span class="tabular-nums text-ink-muted">Page {@page} of {@pages}</span>
      <.link
        :if={@page < @pages}
        id={"#{@id}-next"}
        patch={@path.(@page + 1)}
        class="inline-flex items-center gap-1 text-ink-muted hover:text-ink"
      >
        Next <.icon name="hero-chevron-right-mini" />
      </.link>
    </nav>
    """
  end

  ## Charts

  @doc """
  Bar sparkline of daily counts, e.g. alerts raised per day. Always renders a text
  summary (`summary`) and an aria-label; renders an empty state when every count is 0.
  """
  attr :id, :string, required: true
  attr :points, :list, required: true, doc: "[%{date: Date.t(), count: integer}]"
  attr :summary, :string, required: true
  attr :empty_title, :string, default: "Nothing in this period"

  def sparkline(assigns) do
    max = assigns.points |> Enum.map(& &1.count) |> Enum.max(fn -> 0 end)
    count = length(assigns.points)
    assigns = assign(assigns, max: max, count: count)

    ~H"""
    <figure id={@id} class="w-full">
      <figcaption class="sr-only">{@summary}</figcaption>
      <p class="text-sm text-ink-muted" data-summary>{@summary}</p>
      <%= if @max == 0 do %>
        <.empty_state title={@empty_title} icon="hero-chart-bar" class="py-6" />
      <% else %>
        <svg
          viewBox={"0 0 #{@count * 10} 60"}
          preserveAspectRatio="none"
          class="mt-3 h-24 w-full text-accent"
          role="img"
          aria-label={@summary}
        >
          <rect
            :for={{point, i} <- Enum.with_index(@points)}
            x={i * 10 + 1.5}
            y={60 - bar_height(point.count, @max)}
            width="7"
            height={bar_height(point.count, @max)}
            rx="1.5"
            class={[
              "fill-current transition-opacity hover:opacity-100",
              if(point.count == 0, do: "opacity-15", else: "opacity-70")
            ]}
          >
            <title>{Calendar.strftime(point.date, "%b %-d")}: {point.count}</title>
          </rect>
        </svg>
        <div class="mt-1 flex justify-between text-xs text-ink-faint tabular-nums">
          <span>{Calendar.strftime(List.first(@points).date, "%b %-d")}</span>
          <span>{Calendar.strftime(List.last(@points).date, "%b %-d")}</span>
        </div>
      <% end %>
    </figure>
    """
  end

  defp bar_height(0, _max), do: 2
  defp bar_height(count, max), do: max(round(count / max * 56), 3)

  @days ~w(Mon Tue Wed Thu Fri Sat Sun)

  @doc """
  7×24 heatmap of activity by weekday and hour (UTC), from
  `%{cells: %{{day, hour} => count}, max: n, busiest: text | nil}`. Always renders the
  busiest-period text.
  """
  attr :id, :string, required: true
  attr :heatmap, :map, required: true

  def heatmap(assigns) do
    summary =
      case assigns.heatmap.busiest do
        nil -> "No recorded posting activity."
        busiest -> "Busiest: #{busiest}"
      end

    assigns = assign(assigns, summary: summary, days: Enum.with_index(@days, 1))

    ~H"""
    <figure id={@id} class="w-full">
      <p class="text-sm text-ink-muted" data-summary>{@summary}</p>
      <div
        :if={@heatmap.max > 0}
        class="mt-3 overflow-x-auto"
        role="img"
        aria-label={"Posting activity by weekday and hour, UTC. #{@summary}"}
      >
        <div class="grid min-w-[36rem] grid-cols-[2.5rem_repeat(24,minmax(0,1fr))] gap-0.5 text-[10px] text-ink-faint">
          <span></span>
          <span :for={hour <- 0..23} class="text-center tabular-nums">
            {if rem(hour, 3) == 0, do: String.pad_leading("#{hour}", 2, "0")}
          </span>
          <%= for {day, d} <- @days do %>
            <span class="self-center pr-1">{day}</span>
            <span
              :for={hour <- 0..23}
              class="aspect-square rounded-[3px] bg-accent"
              style={"opacity: #{cell_opacity(Map.get(@heatmap.cells, {d, hour}, 0), @heatmap.max)}"}
              title={"#{day} #{String.pad_leading("#{hour}", 2, "0")}:00 UTC: #{Map.get(@heatmap.cells, {d, hour}, 0)} posts"}
            ></span>
          <% end %>
        </div>
      </div>
    </figure>
    """
  end

  defp cell_opacity(0, _max), do: "0.07"
  defp cell_opacity(n, max), do: :erlang.float_to_binary(0.18 + 0.82 * n / max, decimals: 2)

  @doc """
  SVG graph of linked accounts from `Dripstone.Tracker.network_graph/1`. Edges are
  colored by link kind; `hidden_kinds` are not drawn and nodes left with no visible
  edge are dimmed. Clicking a node sends `select_node` with its id.
  """
  attr :id, :string, required: true
  attr :graph, :map, required: true
  attr :selected, :string, default: nil
  attr :hidden_kinds, :any, default: MapSet.new()
  attr :labels, :map, default: %{}, doc: "account id => handle, for node titles"

  def network_graph(assigns) do
    visible = Enum.reject(assigns.graph.edges, &(&1.kind in assigns.hidden_kinds))
    connected = visible |> Enum.flat_map(&[&1.a, &1.b]) |> MapSet.new()
    positions = Map.new(assigns.graph.nodes, &{&1.id, {&1.x, &1.y}})

    neighbours =
      for edge <- visible, assigns.selected in [edge.a, edge.b], into: MapSet.new() do
        if edge.a == assigns.selected, do: edge.b, else: edge.a
      end

    assigns =
      assign(assigns,
        visible: visible,
        connected: connected,
        positions: positions,
        neighbours: neighbours
      )

    ~H"""
    <svg
      id={@id}
      viewBox="0 0 1000 1000"
      class="h-auto w-full select-none"
      role="img"
      aria-label={"Graph of #{length(@graph.nodes)} linked accounts and #{length(@visible)} links"}
    >
      <line
        :for={edge <- @visible}
        x1={x(@positions, edge.a)}
        y1={y(@positions, edge.a)}
        x2={x(@positions, edge.b)}
        y2={y(@positions, edge.b)}
        style={"stroke: var(--color-link-#{kind_slug(edge.kind)})"}
        stroke-width={if(@selected in [edge.a, edge.b], do: 3, else: 1.4)}
        stroke-opacity={edge_opacity(@selected, edge)}
        data-kind={edge.kind}
      />
      <g
        :for={node <- @graph.nodes}
        id={"#{@id}-node-#{node.id}"}
        phx-click="select_node"
        phx-value-id={node.id}
        class="cursor-pointer"
        data-selected={node.id == @selected}
      >
        <circle
          cx={round(node.x * 1000)}
          cy={round(node.y * 1000)}
          r={node_radius(node, @selected)}
          class={[
            "stroke-surface transition-[r]",
            node_fill(node.id, @selected, @neighbours, @connected)
          ]}
          stroke-width="2"
        />
        <title>{Map.get(@labels, node.id, node.id)} · {node.degree} links</title>
      </g>
    </svg>
    """
  end

  @doc "Legend label for a link kind."
  def link_kind_label(:shared_link), do: "Shared link"
  def link_kind_label(:repost_ring), do: "Repost ring"
  def link_kind_label(:timing_sync), do: "Timing sync"
  def link_kind_label(:audience_overlap), do: "Audience overlap"
  def link_kind_label(:near_duplicate), do: "Near-duplicate content"
  def link_kind_label(:created_together), do: "Created together"
  def link_kind_label(other), do: other |> to_string() |> String.replace("_", " ")

  @doc "CSS-variable slug for a link kind, e.g. `shared-link`."
  def kind_slug(kind) when is_atom(kind) do
    if kind in Link.kinds(),
      do: kind |> Atom.to_string() |> String.replace("_", "-"),
      else: "shared-link"
  end

  def kind_slug(_kind), do: "shared-link"

  @doc "All link kinds, in legend order."
  def link_kinds, do: Link.kinds()

  defp x(positions, id), do: positions |> Map.fetch!(id) |> elem(0) |> Kernel.*(1000) |> round()
  defp y(positions, id), do: positions |> Map.fetch!(id) |> elem(1) |> Kernel.*(1000) |> round()

  defp edge_opacity(nil, _edge), do: 0.45
  defp edge_opacity(selected, %{a: a, b: b}) when selected in [a, b], do: 0.95
  defp edge_opacity(_selected, _edge), do: 0.12

  defp node_radius(%{id: id}, id), do: 16
  defp node_radius(%{degree: degree}, _selected), do: 6 + min(degree, 8)

  defp node_fill(id, id, _neighbours, _connected), do: "fill-accent"

  defp node_fill(id, selected, neighbours, connected) do
    cond do
      not MapSet.member?(connected, id) -> "fill-ink-faint opacity-30"
      selected && MapSet.member?(neighbours, id) -> "fill-accent-strong"
      selected -> "fill-ink-muted opacity-40"
      true -> "fill-ink-muted"
    end
  end

  ## History and toasts

  @doc "A network's change history, newest first, marked Analyst or System."
  attr :id, :string, required: true
  attr :entries, :list, required: true

  def history_list(assigns) do
    ~H"""
    <ol id={@id} class="divide-y divide-line">
      <li :if={@entries == []} class="py-6 text-center text-sm text-ink-muted">
        No changes recorded yet.
      </li>
      <li :for={entry <- @entries} id={"#{@id}-#{entry.id}"} class="flex items-start gap-3 py-3">
        <span class={[
          "mt-0.5 inline-flex shrink-0 items-center rounded px-1.5 py-0.5 text-[11px] font-semibold uppercase tracking-wide",
          if(entry.actor == :analyst,
            do: "bg-accent-soft text-accent-strong",
            else: "bg-surface-raised text-ink-muted"
          )
        ]}>
          {if entry.actor == :analyst, do: "Analyst", else: "System"}
        </span>
        <div class="min-w-0 flex-1 text-sm">
          <p class="text-ink">{entry.summary}</p>
          <p class="mt-0.5 text-xs text-ink-faint">
            {entry.by} · <.relative_time at={entry.at} />
          </p>
        </div>
      </li>
    </ol>
    """
  end

  @doc "Live alert toasts (newest first); each links to its alert and can be dismissed."
  attr :toasts, :list, required: true, doc: "[%{id, alert_id, title, severity}]"

  def toast_stack(assigns) do
    ~H"""
    <div
      id="toasts"
      class="pointer-events-none fixed right-4 bottom-4 z-40 flex w-80 flex-col gap-2 sm:w-96"
      aria-live="polite"
    >
      <div
        :for={toast <- @toasts}
        id={"toast-#{toast.id}"}
        data-toast
        class="pointer-events-auto flex items-start gap-3 rounded-card border border-sev-high/40 bg-surface p-3 shadow-pop motion-safe:animate-[toast-in_200ms_ease-out]"
      >
        <span class="mt-0.5 text-sev-high"><.icon name="hero-bell-alert" class="size-5" /></span>
        <div class="min-w-0 flex-1">
          <p class="text-xs font-semibold uppercase tracking-wide text-sev-high">
            New high-severity alert
          </p>
          <p class="mt-0.5 truncate text-sm font-medium text-ink">{toast.title}</p>
          <.link
            navigate={"/alerts/#{toast.alert_id}"}
            class="mt-1 inline-flex items-center gap-1 text-sm text-accent hover:underline"
          >
            View alert <.icon name="hero-arrow-right-mini" class="size-3.5" />
          </.link>
        </div>
        <button
          type="button"
          phx-click="dismiss_toast"
          phx-value-id={toast.id}
          class="rounded p-1 text-ink-faint hover:text-ink cursor-pointer"
          aria-label="Dismiss"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>
    """
  end
end
