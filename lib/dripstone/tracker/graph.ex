defmodule Dripstone.Tracker.Graph do
  @moduledoc """
  Layout of a network's linked-account graph for the Graph view.

  Keeps the 150 most-linked members (ties broken by account id), then places them
  with a Fruchterman–Reingold force layout (kept inside the frame, with a pull toward
  the centre) seeded from the network id, so the same network and membership always
  produce the same picture. Coordinates are in 0..1.
  """

  alias Dripstone.Tracker.{Link, Network}

  @max_nodes 150
  @iterations 200
  # Pull toward the centre, strong enough to stop the combined repulsion pinning
  # nodes against the frame. Tuned on the 400-member sample network: 0 overlapping
  # nodes, median spacing about 0.055 (was 0.004 without it).
  @gravity 5.0
  # Ideal distance between linked nodes, as a fraction of sqrt(1/n).
  @spacing 0.8

  @type t :: %{
          nodes: [%{id: String.t(), x: float(), y: float(), degree: non_neg_integer()}],
          edges: [%{a: String.t(), b: String.t(), kind: Link.kind(), strength: atom()}],
          total: non_neg_integer(),
          omitted: non_neg_integer()
        }

  @doc "Most nodes the graph draws."
  def max_nodes, do: @max_nodes

  @doc "Cache key: changes whenever the network's membership changes (order-insensitive)."
  def cache_key(%Network{id: id, member_ids: member_ids}),
    do: {:graph, id, :erlang.phash2(Enum.sort(member_ids))}

  @doc "Builds the layout from the network and the full link list."
  @spec build(Network.t(), [Link.t()]) :: t()
  def build(%Network{} = network, links) do
    members = MapSet.new(network.member_ids)

    internal =
      Enum.filter(links, fn %Link{account_ids: {a, b}} -> a in members and b in members end)

    degree =
      Enum.reduce(internal, Map.new(network.member_ids, &{&1, 0}), fn %Link{account_ids: {a, b}},
                                                                      acc ->
        acc |> Map.update!(a, &(&1 + 1)) |> Map.update!(b, &(&1 + 1))
      end)

    drawn =
      network.member_ids
      |> Enum.sort_by(&{-degree[&1], &1})
      |> Enum.take(@max_nodes)

    drawn_set = MapSet.new(drawn)

    edges =
      for %Link{account_ids: {a, b}} = link <- internal,
          a in drawn_set,
          b in drawn_set,
          do: %{a: a, b: b, kind: link.kind, strength: link.strength}

    positions = layout(drawn, edges, :erlang.phash2(network.id))

    nodes =
      Enum.map(drawn, fn id ->
        {x, y} = positions[id]
        %{id: id, x: x, y: y, degree: degree[id]}
      end)

    total = length(network.member_ids)
    %{nodes: nodes, edges: edges, total: total, omitted: total - length(drawn)}
  end

  ## Fruchterman–Reingold

  defp layout([], _edges, _seed), do: %{}
  defp layout([id], _edges, _seed), do: %{id => {0.5, 0.5}}

  defp layout(ids, edges, seed) do
    n = length(ids)
    k = @spacing * :math.sqrt(1.0 / n)
    rand = :rand.seed_s(:exsss, {seed, n, 7})

    {initial, _rand} =
      Enum.map_reduce(ids, rand, fn id, rand ->
        {x, rand} = :rand.uniform_s(rand)
        {y, rand} = :rand.uniform_s(rand)
        {{id, {x, y}}, rand}
      end)

    pairs = edges |> Enum.map(&{&1.a, &1.b}) |> Enum.uniq()

    1..@iterations
    |> Enum.reduce(Map.new(initial), fn i, pos ->
      temperature = 0.1 * (1 - i / (@iterations + 1))
      step(pos, ids, pairs, k, temperature)
    end)
    |> normalize()
  end

  defp step(pos, ids, pairs, k, temperature) do
    points = Enum.map(ids, &{&1, pos[&1]})

    repulsion =
      Map.new(points, fn {id, {x, y}} ->
        Enum.reduce(points, {0.0, 0.0}, fn
          {^id, _}, acc ->
            acc

          {_other, {ox, oy}}, {fx, fy} ->
            {dx, dy, d} = delta(x, y, ox, oy)
            force = k * k / d
            {fx + dx / d * force, fy + dy / d * force}
        end)
        |> then(&{id, &1})
      end)

    forces =
      Enum.reduce(pairs, repulsion, fn {a, b}, acc ->
        {ax, ay} = pos[a]
        {bx, by} = pos[b]
        {dx, dy, d} = delta(ax, ay, bx, by)
        force = d * d / k
        {fx, fy} = {dx / d * force, dy / d * force}

        acc
        |> Map.update!(a, fn {x, y} -> {x - fx, y - fy} end)
        |> Map.update!(b, fn {x, y} -> {x + fx, y + fy} end)
      end)

    Map.new(pos, fn {id, {x, y}} ->
      # A gentle pull toward the centre keeps unlinked nodes from drifting away and
      # squashing everything else when the layout is scaled to fit.
      {fx, fy} = forces[id]
      fx = fx + (0.5 - x) * @gravity
      fy = fy + (0.5 - y) * @gravity
      length = max(:math.sqrt(fx * fx + fy * fy), 1.0e-9)
      move = min(length, temperature)
      {id, {clamp(x + fx / length * move), clamp(y + fy / length * move)}}
    end)
  end

  # Nodes stay inside the frame, as in the original Fruchterman–Reingold layout.
  defp clamp(value), do: value |> max(0.0) |> min(1.0)

  defp delta(x, y, ox, oy) do
    dx = x - ox
    dy = y - oy
    {dx, dy, max(:math.sqrt(dx * dx + dy * dy), 1.0e-4)}
  end

  # Scales positions into 0.05..0.95 so nodes never touch the edge of the canvas.
  defp normalize(pos) do
    {xs, ys} = pos |> Map.values() |> Enum.unzip()
    {min_x, max_x} = Enum.min_max(xs)
    {min_y, max_y} = Enum.min_max(ys)
    span = max(max(max_x - min_x, max_y - min_y), 1.0e-9)

    Map.new(pos, fn {id, {x, y}} ->
      {id, {round4(0.05 + 0.9 * (x - min_x) / span), round4(0.05 + 0.9 * (y - min_y) / span)}}
    end)
  end

  defp round4(value), do: Float.round(value, 4)
end
