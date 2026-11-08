defmodule DripstoneWeb.TrackerComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias DripstoneWeb.TrackerComponents

  defp render(fun, assigns),
    do: render_component(Function.capture(TrackerComponents, fun, 1), assigns)

  defp text(html),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.text() |> String.split() |> Enum.join(" ")

  describe "badges always include a text label" do
    for {severity, label} <- [low: "Low", medium: "Medium", high: "High"] do
      test "severity #{severity}" do
        assert render(:severity_badge, %{severity: unquote(severity), class: nil}) |> text() ==
                 unquote(label)
      end
    end

    for {score, label} <- [
          {12, "Low 12"},
          {40, "Medium 40"},
          {69, "Medium 69"},
          {70, "High 70"},
          {91, "High 91"}
        ] do
      test "risk #{score}" do
        assert render(:risk_badge, %{score: unquote(score), class: nil}) |> text() ==
                 unquote(label)
      end
    end

    for {status, label} <- [
          open: "Open",
          suspected: "Suspected",
          confirmed: "Confirmed",
          dismissed: "Dismissed",
          healthy: "Healthy",
          degraded: "Degraded",
          down: "Down",
          not_connected: "Not connected"
        ] do
      test "status #{status}" do
        assert render(:status_pill, %{status: unquote(status), class: nil}) |> text() ==
                 unquote(label)
      end
    end

    for {strength, label} <- [weak: "Weak", moderate: "Moderate", strong: "Strong"] do
      test "strength #{strength}" do
        assert render(:strength_badge, %{strength: unquote(strength), class: nil}) |> text() ==
                 unquote(label)
      end
    end
  end

  test "platform badges use the feed registry and fall back to the raw id" do
    assert render(:platform_badge, %{feed_id: "mastodon", class: nil}) |> text() == "Mastodon"
    assert render(:platform_badge, %{feed_id: "myspace", class: nil}) |> text() == "myspace"
  end

  test "AI-written text is labeled" do
    html = render(:ai_label, %{generated_at: ~U[2026-11-07 15:00:00Z], class: nil})
    assert text(html) =~ "AI-generated"
  end

  describe "charts render text summaries" do
    test "sparkline shows the summary and an aria-label" do
      points = for d <- 0..29, do: %{date: Date.add(~D[2026-10-09], d), count: rem(d, 4)}

      html =
        render(:sparkline, %{
          id: "trend",
          points: points,
          summary: "41 alerts raised in the last 30 days",
          empty_title: "x"
        })

      assert text(html) =~ "41 alerts raised in the last 30 days"
      assert html =~ ~s(aria-label="41 alerts raised in the last 30 days")
      assert html =~ "<rect"
    end

    test "sparkline with no data shows an empty state instead of a flat line" do
      points = for d <- 0..29, do: %{date: Date.add(~D[2026-10-09], d), count: 0}

      html =
        render(:sparkline, %{
          id: "trend",
          points: points,
          summary: "0 alerts",
          empty_title: "No alerts in the last 30 days"
        })

      refute html =~ "<rect"
      assert text(html) =~ "No alerts in the last 30 days"
    end

    test "heatmap shows the busiest period" do
      heatmap = %{
        cells: %{{1, 9} => 12, {2, 9} => 10, {1, 14} => 1},
        max: 12,
        busiest: "Weekdays 09:00–10:00 UTC"
      }

      html = render(:heatmap, %{id: "hm", heatmap: heatmap})

      assert text(html) =~ "Busiest: Weekdays 09:00–10:00 UTC"
      assert html =~ ~s(role="img")
    end

    test "heatmap with no activity says so" do
      html = render(:heatmap, %{id: "hm", heatmap: %{cells: %{}, max: 0, busiest: nil}})
      assert text(html) =~ "No recorded posting activity."
    end
  end

  describe "helpers" do
    test "relative times" do
      now = ~U[2026-11-07 17:00:00Z]
      assert TrackerComponents.ago(now, now) == "just now"
      assert TrackerComponents.ago(DateTime.add(now, -300), now) == "5m ago"
      assert TrackerComponents.ago(DateTime.add(now, -7_200), now) == "2h ago"
      assert TrackerComponents.ago(DateTime.add(now, -3 * 86_400), now) == "3d ago"
      assert TrackerComponents.ago(~U[2026-01-02 00:00:00Z], now) == "Jan 2, 2026"
    end

    test "numbers get thousands separators" do
      assert TrackerComponents.format_number(1284) == "1,284"
      assert TrackerComponents.format_number(18_204) == "18,204"
      assert TrackerComponents.format_number(7) == "7"
    end
  end

  test "history entries are marked Analyst or System" do
    entries = [
      %{
        id: "h2",
        actor: :system,
        by: "Detection",
        at: ~U[2026-11-07 16:00:00Z],
        summary: "Added 3 members"
      },
      %{
        id: "h1",
        actor: :analyst,
        by: "Unattributed",
        at: ~U[2026-11-07 15:00:00Z],
        summary: "Renamed"
      }
    ]

    html = render(:history_list, %{id: "history", entries: entries})
    assert text(html) =~ "System Added 3 members"
    assert text(html) =~ "Analyst Renamed"
  end

  test "the network graph draws only visible link kinds and dims isolated nodes" do
    graph = %{
      nodes: [
        %{id: "a", x: 0.1, y: 0.1, degree: 2},
        %{id: "b", x: 0.9, y: 0.9, degree: 1},
        %{id: "c", x: 0.5, y: 0.5, degree: 1}
      ],
      edges: [
        %{a: "a", b: "b", kind: :shared_link, strength: :strong},
        %{a: "a", b: "c", kind: :near_duplicate, strength: :weak}
      ],
      total: 3,
      omitted: 0
    }

    assigns = %{graph: graph}

    html =
      rendered_to_string(~H"""
      <TrackerComponents.network_graph
        id="g"
        graph={@graph}
        hidden_kinds={MapSet.new([:near_duplicate])}
      />
      """)

    assert html =~ ~s(data-kind="shared_link")
    refute html =~ ~s(data-kind="near_duplicate")
    assert html =~ "opacity-30", "node c has no visible links and should be dimmed"
  end

  test "graph nodes are focusable buttons activatable with Enter or Space" do
    graph = %{
      nodes: [%{id: "a", x: 0.1, y: 0.1, degree: 2}],
      edges: [],
      total: 1,
      omitted: 0
    }

    assigns = %{graph: graph, labels: %{"a" => "@alice"}}

    html =
      rendered_to_string(~H"""
      <TrackerComponents.network_graph id="g" graph={@graph} labels={@labels} />
      """)

    assert html =~ ~s(role="button")
    assert html =~ ~s(tabindex="0")
    assert html =~ ~s(phx-keydown="select_node_key")
    assert html =~ ~s(aria-label="@alice · 2 links")
  end
end
