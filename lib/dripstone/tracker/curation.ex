defmodule Dripstone.Tracker.Curation do
  @moduledoc """
  Analyst tools for correcting and organizing networks. Pure functions over
  `Dripstone.Tracker.State`, returning `{:ok, reply, state, messages}` or
  `{:error, reason}`. Text inputs that fail validation return
  `{:error, %Ecto.Changeset{}}`.

  Every change is recorded in the network's history as an `:analyst` change.
  Removing or moving members records them in `removed_account_ids`, so later
  detection updates do not re-add them; renaming keeps `detected_name`, so detection
  cannot overwrite the name.
  """

  import Ecto.Changeset

  alias Dripstone.Tracker.{Network, Note, State}

  @by "Detection"
  @max_tags 20
  @tag_format ~r/\A[a-z0-9-]{1,32}\z/
  @status_order [:confirmed, :suspected, :dismissed]

  ## Changesets (also used by forms)

  @doc "Changeset for a network name (1–80 characters)."
  def name_changeset(attrs \\ %{}) do
    {%{}, %{name: :string}}
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name], message: "can't be blank")
    |> validate_length(:name, min: 1, max: 80)
  end

  @doc "Changeset for a note body (1–2,000 characters)."
  def note_changeset(attrs \\ %{}) do
    {%{}, %{body: :string}}
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body], message: "can't be blank")
    |> validate_length(:body, max: 2000)
  end

  @doc "Changeset for a tag; normalizes case and spaces before validating."
  def tag_changeset(attrs \\ %{}) do
    {%{}, %{tag: :string}}
    |> cast(attrs, [:tag])
    |> update_change(:tag, &normalize_tag/1)
    |> validate_required([:tag], message: "can't be blank")
    |> validate_format(:tag, @tag_format,
      message: "use lowercase letters, digits and hyphens (up to 32)"
    )
  end

  @doc "Lowercases a tag and turns runs of spaces or underscores into hyphens."
  @spec normalize_tag(String.t()) :: String.t()
  def normalize_tag(tag),
    do: tag |> String.trim() |> String.downcase() |> String.replace(~r/[\s_]+/, "-")

  ## Name, tags, notes

  def rename(state, id, attrs, now, by \\ @by) do
    with {:ok, network} <- active(state, id),
         {:ok, %{name: name}} <- apply_action(name_changeset(attrs), :update) do
      if name == network.name do
        {:ok, network, state, []}
      else
        updated = %{network | name: name, detected_name: network.detected_name || network.name}

        state
        |> put_network(updated)
        |> history(id, "Renamed #{network.name} → #{name}", now, by)
        |> done(updated, [id])
      end
    end
  end

  def add_tag(state, id, attrs, now, by \\ @by) do
    with {:ok, network} <- active(state, id),
         {:ok, %{tag: tag}} <- apply_action(tag_changeset(attrs), :insert) do
      cond do
        tag in network.tags ->
          {:ok, network, state, []}

        length(network.tags) >= @max_tags ->
          {:error,
           add_error(tag_changeset(attrs), :tag, "a network can have at most #{@max_tags} tags")
           |> Map.put(:action, :insert)}

        true ->
          updated = %{network | tags: network.tags ++ [tag]}

          state
          |> put_network(updated)
          |> history(id, "Tagged ##{tag}", now, by)
          |> done(updated, [id])
      end
    end
  end

  def remove_tag(state, id, tag, now, by \\ @by) do
    with {:ok, network} <- active(state, id) do
      if tag in network.tags do
        updated = %{network | tags: List.delete(network.tags, tag)}

        state
        |> put_network(updated)
        |> history(id, "Removed tag ##{tag}", now, by)
        |> done(updated, [id])
      else
        {:ok, network, state, []}
      end
    end
  end

  def add_note(state, id, attrs, now, by \\ @by) do
    with {:ok, _network} <- active(state, id),
         {:ok, %{body: body}} <- apply_action(note_changeset(attrs), :insert) do
      {note_id, state} = State.next_id(state, "note")
      note = %Note{id: note_id, network_id: id, body: body, by: by, at: now}

      %{state | notes: Map.put(state.notes, note_id, note)}
      |> history(id, "Added a note", now, by)
      |> done(note, [id])
    end
  end

  ## Membership

  def add_members(state, id, account_ids, now, by \\ @by) do
    with {:ok, network} <- active(state, id),
         :ok <- known_accounts(state, account_ids) do
      new_ids = Enum.uniq(account_ids) -- network.member_ids

      if new_ids == [] do
        {:ok, network, state, []}
      else
        updated = join(network, new_ids, now)

        state
        |> put_network(updated)
        |> history(id, "Added #{count(new_ids, "member")}", now, by)
        |> done(updated, [id])
      end
    end
  end

  def remove_members(state, id, account_ids, now, by \\ @by) do
    with {:ok, network} <- active(state, id),
         {:ok, ids} <- members(network, account_ids) do
      updated = leave(network, ids)

      state
      |> put_network(updated)
      |> history(id, "Removed #{count(ids, "member")}", now, by)
      |> done(updated, [id])
    end
  end

  def move_members(state, from_id, to_id, account_ids, now, by \\ @by) do
    with :ok <- distinct(from_id, to_id),
         {:ok, from} <- active(state, from_id),
         {:ok, to} <- active(state, to_id),
         {:ok, ids} <- members(from, account_ids) do
      from = leave(from, ids)
      to = join(to, ids, now)
      moved = count(ids, "member")

      state
      |> put_network(from)
      |> put_network(to)
      |> history(from_id, "Moved #{moved} to #{to.name}", now, by)
      |> history(to_id, "Received #{moved} from #{from.name}", now, by)
      |> done(%{from: from, to: to}, [from_id, to_id])
    end
  end

  ## Merge, split, relate

  def merge(state, source_id, target_id, now, by \\ @by) do
    with :ok <- distinct(source_id, target_id),
         {:ok, source} <- active(state, source_id),
         {:ok, target} <- active(state, target_id) do
      merged = %{
        target
        | member_ids: Enum.uniq(target.member_ids ++ source.member_ids),
          joined_at: Map.merge(source.joined_at, target.joined_at),
          platforms: Enum.uniq(target.platforms ++ source.platforms),
          tags: Enum.uniq(target.tags ++ source.tags),
          evidence: target.evidence ++ source.evidence,
          related_ids:
            Enum.uniq(target.related_ids ++ source.related_ids) -- [target_id, source_id],
          removed_account_ids:
            Enum.uniq(target.removed_account_ids ++ source.removed_account_ids) --
              source.member_ids,
          confidence: max(target.confidence, source.confidence),
          status: Enum.find(@status_order, &(&1 in [target.status, source.status])),
          first_activity_at: earliest(target.first_activity_at, source.first_activity_at),
          last_activity_at: latest(target.last_activity_at, source.last_activity_at)
      }

      retired = %{source | retired_into: target_id, related_ids: []}

      backrefs =
        for {id, n} <- state.networks,
            id != source_id and id != target_id and source_id in n.related_ids,
            do: id

      state
      |> rewire_related(source_id, target_id)
      |> put_network(merged)
      |> put_network(retired)
      |> reassign(source_id, target_id)
      |> history(target_id, "Merged in #{source.name}", now, by)
      |> history(source_id, "Merged into #{target.name}", now, by)
      |> done(merged, [target_id, source_id | Enum.uniq(backrefs ++ source.related_ids)])
    end
  end

  def split(state, id, account_ids, attrs, now, by \\ @by) do
    with {:ok, network} <- active(state, id),
         {:ok, ids} <- members(network, account_ids),
         :ok <-
           if(length(ids) < length(network.member_ids),
             do: :ok,
             else: {:error, :cannot_split_all}
           ),
         {:ok, %{name: name}} <- apply_action(name_changeset(attrs), :insert) do
      {new_id, state} = State.next_id(state, "net-split")

      split = %Network{
        id: new_id,
        name: name,
        status: network.status,
        confidence: network.confidence,
        member_ids: ids,
        joined_at: Map.new(ids, &{&1, now}),
        platforms: ids |> Enum.map(&state.accounts[&1].feed_id) |> Enum.uniq(),
        main_domain: network.main_domain,
        first_activity_at: network.first_activity_at,
        last_activity_at: network.last_activity_at,
        inserted_at: now
      }

      state
      |> put_network(leave(network, ids))
      |> put_network(split)
      |> history(id, "Split #{count(ids, "member")} into #{name}", now, by)
      |> history(new_id, "Split from #{network.name} with #{count(ids, "member")}", now, by)
      |> done(split, [id, new_id])
    end
  end

  def relate(state, a_id, b_id, note, now, by \\ @by) do
    with :ok <- distinct(a_id, b_id),
         {:ok, a} <- active(state, a_id),
         {:ok, b} <- active(state, b_id) do
      suffix =
        if is_binary(note) and String.trim(note) != "", do: ": " <> String.trim(note), else: ""

      a = %{a | related_ids: Enum.uniq(a.related_ids ++ [b_id])}
      b = %{b | related_ids: Enum.uniq(b.related_ids ++ [a_id])}

      state
      |> put_network(a)
      |> put_network(b)
      |> history(a_id, "Marked related to #{b.name}#{suffix}", now, by)
      |> history(b_id, "Marked related to #{a.name}#{suffix}", now, by)
      |> done(a, [a_id, b_id])
    end
  end

  def unrelate(state, a_id, b_id, now, by \\ @by) do
    with {:ok, a} <- active(state, a_id),
         {:ok, b} <- active(state, b_id) do
      a = %{a | related_ids: List.delete(a.related_ids, b_id)}
      b = %{b | related_ids: List.delete(b.related_ids, a_id)}

      state
      |> put_network(a)
      |> put_network(b)
      |> history(a_id, "No longer related to #{b.name}", now, by)
      |> history(b_id, "No longer related to #{a.name}", now, by)
      |> done(a, [a_id, b_id])
    end
  end

  ## Helpers

  defp active(state, id) do
    case state.networks do
      %{^id => %Network{retired_into: nil} = network} -> {:ok, network}
      %{^id => %Network{}} -> {:error, :retired}
      _ -> {:error, :not_found}
    end
  end

  defp distinct(id, id), do: {:error, :same_network}
  defp distinct(_a, _b), do: :ok

  defp known_accounts(state, ids) do
    if ids != [] and Enum.all?(ids, &Map.has_key?(state.accounts, &1)),
      do: :ok,
      else: {:error, :unknown_account}
  end

  defp members(network, ids) do
    ids = Enum.uniq(ids)

    cond do
      ids == [] -> {:error, :no_members_selected}
      Enum.all?(ids, &(&1 in network.member_ids)) -> {:ok, ids}
      true -> {:error, :not_a_member}
    end
  end

  defp join(network, ids, now) do
    ids = ids -- network.member_ids

    %{
      network
      | member_ids: network.member_ids ++ ids,
        joined_at: Map.merge(network.joined_at, Map.new(ids, &{&1, now})),
        removed_account_ids: network.removed_account_ids -- ids
    }
  end

  defp leave(network, ids) do
    %{
      network
      | member_ids: network.member_ids -- ids,
        joined_at: Map.drop(network.joined_at, ids),
        removed_account_ids: Enum.uniq(network.removed_account_ids ++ ids)
    }
  end

  # Moves alerts, decisions and notes of `from` onto `to`.
  defp reassign(state, from, to) do
    move = fn map ->
      Map.new(map, fn {k, v} ->
        {k, if(v.network_id == from, do: %{v | network_id: to}, else: v)}
      end)
    end

    %{
      state
      | alerts: move.(state.alerts),
        decisions: move.(state.decisions),
        notes: move.(state.notes)
    }
    |> State.reindex()
  end

  # Points back-references at `from` onto `to` (or prunes them when already linked).
  defp rewire_related(state, from, to) do
    %{state | networks: Map.new(state.networks, &rewire_one(&1, from, to))}
  end

  defp rewire_one({id, n}, from, to) when id != from and id != to do
    if from in n.related_ids do
      {id, %{n | related_ids: Enum.uniq(List.delete(n.related_ids, from) ++ [to]) -- [id]}}
    else
      {id, n}
    end
  end

  defp rewire_one(entry, _from, _to), do: entry

  defp put_network(state, network),
    do: %{state | networks: Map.put(state.networks, network.id, network)}

  defp history(state, id, summary, now, by),
    do: State.add_history(state, id, :analyst, by, summary, now)

  defp done(state, reply, network_ids),
    do: {:ok, reply, state, network_ids |> Enum.uniq() |> Enum.map(&{:network_updated, &1})}

  @doc "Counts items with a noun (1 member, 3 members)."
  def count(1, noun), do: "1 #{noun}"
  def count(n, noun) when is_integer(n), do: "#{n} #{noun}s"
  def count([_], noun), do: "1 #{noun}"
  def count(list, noun), do: "#{length(list)} #{noun}s"

  defp earliest(nil, b), do: b
  defp earliest(a, nil), do: a
  defp earliest(a, b), do: if(DateTime.before?(a, b), do: a, else: b)

  defp latest(nil, b), do: b
  defp latest(a, nil), do: a
  defp latest(a, b), do: if(DateTime.after?(a, b), do: a, else: b)
end
