defmodule Dripstone.Tracker.Report do
  @moduledoc """
  A validated finding as detection reports it (see `openspec/docs/DETECTION_INTERFACE.md`):
  an **account**, **group** or **trend** finding carrying heuristics and the decision
  model's answers map exactly as returned (or `nil` when the AI was unavailable).

  `cast/2` accepts a plain map with all-atom or all-string keys, so a decoded JSON
  payload works as-is, and checks it against the known feeds and networks. It
  returns `{:ok, %Report{}}` or `{:error, errors}` (field => messages) and never
  raises on bad input. `Dripstone.Tracker.Rules` decides what a report means.
  """

  import Ecto.Changeset, except: [cast: 3]

  alias Dripstone.Feeds
  alias Dripstone.Tracker.{Answers, State}

  @enforce_keys [:kind, :observed_at]
  defstruct [
    :kind,
    :observed_at,
    :model,
    :network_id,
    :account,
    :answers,
    :raw_answers,
    :window,
    accounts: [],
    posts: [],
    heuristics: %{score: nil, labels: [], domains: []}
  ]

  @type ref :: %{feed_id: String.t(), handle: String.t()}
  @type t :: %__MODULE__{
          kind: :account | :group | :trend,
          observed_at: DateTime.t(),
          model: String.t() | nil,
          network_id: String.t() | nil,
          account: ref() | nil,
          accounts: [ref()],
          posts: [map()],
          heuristics: %{score: number() | nil, labels: [String.t()], domains: [map()]},
          answers: Answers.parsed() | nil,
          raw_answers: map() | nil,
          window: map() | nil
        }

  @types %{
    kind: :string,
    observed_at: :utc_datetime,
    model: :string,
    network_id: :string,
    account: :map,
    accounts: {:array, :map},
    posts: {:array, :map},
    heuristics: :map,
    answers: :map,
    window: :map
  }

  # Validated values, put on the changeset but never cast from input.
  @parsed %{
    parsed_answers: :map,
    parsed_heuristics: :map,
    parsed_account: :map,
    parsed_accounts: {:array, :map},
    parsed_posts: {:array, :map}
  }

  @kinds %{"account" => :account, "group" => :group, "trend" => :trend}

  @doc "Validates `attrs` against the feeds registry and the networks in `state`."
  @spec cast(map(), State.t()) :: {:ok, t()} | {:error, %{atom() => [String.t()]}}
  def cast(attrs, %State{} = state) when is_map(attrs) do
    changeset =
      {%{}, Map.merge(@types, @parsed)}
      |> Ecto.Changeset.cast(attrs, Map.keys(@types))
      |> validate_required([:kind, :observed_at])
      |> validate_inclusion(:kind, Map.keys(@kinds), message: "must be account, group or trend")
      |> validate_answers()
      |> validate_heuristics()
      |> validate_kind(state)

    if changeset.valid?, do: {:ok, build(changeset)}, else: {:error, errors(changeset)}
  rescue
    Ecto.CastError -> {:error, %{base: ["keys must be all atoms or all strings"]}}
  end

  def cast(_attrs, _state), do: {:error, %{base: ["a finding must be a map"]}}

  ## Fields shared by every kind

  defp validate_answers(changeset) do
    case Answers.parse(get_field(changeset, :answers)) do
      {:ok, parsed} -> put_change(changeset, :parsed_answers, parsed)
      {:error, message} -> add_error(changeset, :answers, message)
    end
  end

  defp validate_heuristics(changeset) do
    heuristics = get_field(changeset, :heuristics) || %{}
    score = get(heuristics, :score)
    labels = get(heuristics, :labels) || []
    domains = get(heuristics, :domains) || []

    cond do
      not (is_nil(score) or (is_number(score) and score >= 0 and score <= 100)) ->
        add_error(changeset, :heuristics, "score must be a number from 0 to 100")

      not strings?(labels) ->
        add_error(changeset, :heuristics, "labels must be a list of strings")

      not domains?(domains) ->
        add_error(
          changeset,
          :heuristics,
          "domains must be a list of %{domain, share} with share from 0 to 1"
        )

      true ->
        put_change(changeset, :parsed_heuristics, %{
          score: score,
          labels: labels,
          domains: Enum.map(domains, &%{domain: get(&1, :domain), share: get(&1, :share) / 1})
        })
    end
  end

  ## Per-kind fields

  # Runs even when other fields are invalid, so every problem is reported at once.
  defp validate_kind(changeset, state) do
    case Map.fetch(@kinds, get_field(changeset, :kind)) do
      {:ok, :account} -> validate_account(changeset)
      {:ok, :group} -> validate_group(changeset, state)
      {:ok, :trend} -> validate_trend(changeset, state)
      :error -> changeset
    end
  end

  defp validate_account(changeset) do
    changeset =
      case ref(get_field(changeset, :account)) do
        {:ok, ref} -> put_change(changeset, :parsed_account, ref)
        {:error, message} -> add_error(changeset, :account, message)
      end

    case all_ok(get_field(changeset, :posts) || [], &post/1) do
      {:ok, posts} -> put_change(changeset, :parsed_posts, posts)
      {:error, message} -> add_error(changeset, :posts, message)
    end
  end

  defp validate_group(changeset, state) do
    changeset =
      case all_ok(get_field(changeset, :accounts) || [], &ref/1) do
        {:ok, refs} ->
          refs = Enum.uniq(refs)

          if length(refs) >= 2,
            do: put_change(changeset, :parsed_accounts, refs),
            else: add_error(changeset, :accounts, "a group needs at least two different accounts")

        {:error, message} ->
          add_error(changeset, :accounts, message)
      end

    case get_field(changeset, :network_id) do
      nil -> changeset
      id -> validate_network(changeset, id, state)
    end
  end

  defp validate_trend(changeset, state) do
    case get_field(changeset, :network_id) do
      nil -> add_error(changeset, :network_id, "a trend finding needs a network_id")
      id -> validate_network(changeset, id, state)
    end
  end

  defp validate_network(changeset, id, state) do
    case state.networks[id] do
      nil ->
        add_error(changeset, :network_id, "unknown network #{inspect(id)}")

      %{retired_into: into} when is_binary(into) ->
        add_error(
          changeset,
          :network_id,
          "network #{inspect(id)} was merged into #{inspect(into)}"
        )

      _network ->
        changeset
    end
  end

  # An account reference: %{feed_id, handle} on a registered feed.
  defp ref(%{} = ref) do
    feed_id = get(ref, :feed_id)
    handle = get(ref, :handle)

    cond do
      not text?(feed_id) -> {:error, "feed_id can't be blank"}
      not text?(handle) -> {:error, "handle can't be blank"}
      is_nil(Feeds.get(feed_id)) -> {:error, "unknown feed #{inspect(feed_id)}"}
      true -> {:ok, %{feed_id: feed_id, handle: handle}}
    end
  end

  defp ref(nil), do: {:error, "is required for an account finding"}
  defp ref(_ref), do: {:error, "must be a map with feed_id and handle"}

  defp post(%{} = post) do
    id = get(post, :id)
    urls = get(post, :urls) || []

    cond do
      not (text?(id) or is_integer(id)) ->
        {:error, "id can't be blank"}

      not strings?(urls) ->
        {:error, "urls must be a list of strings"}

      true ->
        {:ok,
         %{
           id: to_string(id),
           published_at: get(post, :published_at),
           urls: urls,
           text: text_or_nil(get(post, :text))
         }}
    end
  end

  defp post(_post), do: {:error, "must be a map"}

  ## Building

  defp build(changeset) do
    fields = apply_changes(changeset)

    %__MODULE__{
      kind: Map.fetch!(@kinds, fields.kind),
      observed_at: DateTime.truncate(fields.observed_at, :second),
      model: Map.get(fields, :model),
      network_id: Map.get(fields, :network_id),
      account: Map.get(fields, :parsed_account),
      accounts: Map.get(fields, :parsed_accounts, []),
      posts: Map.get(fields, :parsed_posts, []),
      heuristics: Map.fetch!(fields, :parsed_heuristics),
      answers: Map.get(fields, :parsed_answers),
      raw_answers: Map.get(fields, :answers),
      window: Map.get(fields, :window)
    }
  end

  defp errors(changeset) do
    traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", format(value))
      end)
    end)
  end

  # Same crash as Finding.errors/1: cast failures keep non-string values (like
  # `{:array, :map}`) in the message options, and `to_string/1` on them raises.
  defp format(value) when is_binary(value), do: value
  defp format(value) when is_atom(value) or is_number(value), do: to_string(value)
  defp format(value), do: inspect(value)

  ## Helpers

  # Reads a key given as an atom or its string form, without creating atoms.
  defp get(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp get(_value, _key), do: nil

  defp all_ok(items, fun) when is_list(items) do
    items
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {item, n}, {:ok, acc} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, message} -> {:halt, {:error, "item #{n}: #{message}"}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp domains?(domains) when is_list(domains) do
    Enum.all?(domains, fn d ->
      is_map(d) and text?(get(d, :domain)) and is_number(get(d, :share)) and
        get(d, :share) >= 0 and get(d, :share) <= 1
    end)
  end

  defp domains?(_domains), do: false

  defp text?(value), do: is_binary(value) and String.trim(value) != ""
  defp text_or_nil(value) when is_binary(value), do: value
  defp text_or_nil(_value), do: nil
  defp strings?(value), do: is_list(value) and Enum.all?(value, &is_binary/1)
end
