defmodule Dripstone.Showcase do
  @moduledoc """
  Hand-built demo corpus under `priv/datasets/showcase/`.

  `v1.json` holds linked accounts, their posts, and the Jev-style relation
  findings (`repost-ring`, `shared-link`, `timing-sync`, `none`) that justify
  the links. `load/1` replays the corpus through the real tracker paths —
  `Intake` for findings, with accounts/posts seeded as plain state — so the
  overview screen renders the resulting linked networks.

  Separate from the scraped corpora under `priv/datasets/<platform>/`: this
  one is versioned by hand and tells the data-in-relations-out story.
  """

  alias Dripstone.Tracker.{Account, Intake, Link, Post, Signal, State}

  @corpus "v1.json"

  @doc "Loads the named showcase corpus file into a tracker state."
  @spec load(String.t()) :: {:ok, State.t()} | {:error, term()}
  def load(name \\ @corpus) do
    with {:ok, raw} <- File.read(corpus_path(name)),
         {:ok, corpus} <- Jason.decode(raw) do
      load_corpus(corpus)
    end
  end

  @doc "Corpus path for a showcase file (tests override the dir)."
  @spec corpus_path(String.t(), keyword()) :: Path.t()
  def corpus_path(name, opts \\ []) do
    dir =
      Keyword.get(opts, :showcase_dir, Path.join([File.cwd!(), "priv", "datasets", "showcase"]))

    Path.join(dir, name)
  end

  defp load_corpus(%{"accounts" => accounts, "findings" => findings}) do
    empty = %State{}

    with {:ok, state} <- seed_accounts(empty, accounts) do
      replay_findings(state, findings)
    end
  end

  defp load_corpus(_corpus), do: {:error, :invalid_corpus}

  defp seed_accounts(state, accounts) when is_list(accounts) do
    state =
      Enum.reduce(accounts, state, fn raw, state ->
        {:ok, state} = seed_account(state, raw)
        state
      end)

    {:ok, state}
  end

  defp seed_account(state, raw) when is_map(raw) do
    posts = Enum.map(raw["posts"] || [], &post(raw["id"], &1))

    with {:ok, seen} <- last_seen(posts) do
      account = %Account{
        id: raw["id"],
        feed_id: raw["feed_id"],
        handle: raw["handle"],
        display_name: raw["display_name"],
        instance: raw["instance"],
        created_at: nil,
        first_seen_at: first_seen(posts),
        last_seen_at: seen,
        assessment: nil,
        risk_score: raw["risk_score"] || 0,
        signals: Enum.map(raw["signals"] || [], &signal/1)
      }

      {:ok,
       %{
         state
         | accounts: Map.put(state.accounts, account.id, account),
           posts:
             Map.put(
               state.posts,
               account.id,
               Enum.sort_by(posts, & &1.posted_at, {:desc, DateTime})
             )
       }}
    end
  end

  defp post(account_id, raw) do
    %Post{
      id: "#{account_id}/#{raw["post_id"]}",
      account_id: account_id,
      post_id: raw["post_id"],
      posted_at: parse_time!(raw["posted_at"]),
      text: raw["text"],
      domain: raw["domain"]
    }
  end

  defp signal(raw) do
    %Signal{name: raw["name"], explanation: raw["explanation"], contribution: raw["contribution"]}
  end

  defp first_seen([]), do: nil
  defp first_seen(posts), do: posts |> Enum.map(& &1.posted_at) |> Enum.min(DateTime)

  defp last_seen([]), do: {:ok, nil}
  defp last_seen(posts), do: {:ok, posts |> Enum.map(& &1.posted_at) |> Enum.max(DateTime)}

  defp parse_time!(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> DateTime.truncate(at, :second)
      _ -> raise ArgumentError, "showcase corpus has invalid posted_at #{inspect(iso)}"
    end
  end

  defp replay_findings(state, findings) when is_list(findings) do
    state =
      Enum.reduce(findings, state, fn raw, state ->
        {links, finding} = Map.pop(raw, "links", [])
        {:ok, %{network_id: network_id}, state} = Intake.run(state, finding, observed_at!(raw))
        put_links(state, network_id, links)
      end)

    {:ok, state}
  end

  # Optional per-finding `"links"` list (pair + scorer relation label + strength)
  # becomes `Dripstone.Tracker.Link` rows on the loaded state. Intake runs the
  # real path; links are the relation labels it produced.
  defp put_links(state, _network_id, []), do: state

  defp put_links(state, _network_id, links) do
    rows =
      Enum.map(links, fn %{"a" => a, "b" => b, "relation" => relation} = raw ->
        {x, y} = if a <= b, do: {a, b}, else: {b, a}

        %Link{
          account_ids: {x, y},
          kind: Link.relation_kind(relation),
          strength: strength(raw["strength"])
        }
      end)

    %{state | links: Enum.uniq(state.links ++ rows)}
  end

  defp strength("weak"), do: :weak
  defp strength("moderate"), do: :moderate
  defp strength(_strength), do: :strong

  defp observed_at!(%{"observed_at" => iso}) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> DateTime.truncate(at, :second)
      _ -> raise ArgumentError, "showcase corpus has invalid observed_at #{inspect(iso)}"
    end
  end
end
