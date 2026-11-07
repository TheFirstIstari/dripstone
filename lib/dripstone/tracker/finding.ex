defmodule Dripstone.Tracker.Finding do
  @moduledoc """
  A validated finding reported by detection (see `openspec/changes/add-tracker-ui/docs/DETECTION_INTERFACE.md`).

  `cast/2` accepts a plain map with all-atom or all-string keys (so a decoded JSON
  payload works as-is) and validates it against the trigger catalog and the known
  networks. It returns `{:ok, %Finding{}}` or `{:error, errors}`, where `errors` is
  a map of field => list of messages.
  """

  import Ecto.Changeset, except: [cast: 3]

  alias Dripstone.Alerts
  alias Dripstone.Tracker.Evidence

  @enforce_keys [:trigger_id, :severity, :title, :observed_at, :evidence]
  defstruct [
    :trigger_id,
    :severity,
    :title,
    :observed_at,
    :network_id,
    :new_network,
    :ai_rationale,
    :comparison,
    :network_updates,
    evidence: []
  ]

  @type t :: %__MODULE__{}

  @types %{
    trigger: :string,
    severity: :string,
    title: :string,
    observed_at: :utc_datetime,
    network_id: :string,
    new_network: :map,
    evidence: {:array, :map},
    ai_rationale: :map,
    comparison: :map,
    network_updates: :map
  }

  @severities %{"low" => :low, "medium" => :medium, "high" => :high}
  @strengths %{"weak" => :weak, "moderate" => :moderate, "strong" => :strong}
  @kinds Map.new(
           [:shared_link, :near_duplicate, :synced_posting, :created_together, :other],
           &{Atom.to_string(&1), &1}
         )

  @doc """
  Validates `attrs` against the trigger catalog, `networks` (a map of known
  network ids) and `accounts` (a map of known account ids). Never raises on bad input.
  """
  @spec cast(map(), map(), map()) :: {:ok, t()} | {:error, %{atom() => [String.t()]}}
  def cast(attrs, networks, accounts \\ %{})

  def cast(attrs, networks, accounts) when is_map(attrs) do
    changeset =
      {%{}, @types}
      |> Ecto.Changeset.cast(attrs, Map.keys(@types))
      |> validate_required([:trigger, :severity, :title, :observed_at])
      |> validate_length(:title, max: 200)
      |> validate_inclusion(:severity, Map.keys(@severities),
        message: "must be low, medium or high"
      )
      |> validate_trigger()
      |> validate_evidence()
      |> validate_network(networks, accounts)
      |> validate_nested(:ai_rationale, &rationale/1)
      |> validate_nested(:comparison, &comparison/1)

    if changeset.valid?, do: {:ok, build(changeset)}, else: {:error, errors(changeset)}
  rescue
    Ecto.CastError -> {:error, %{base: ["keys must be all atoms or all strings"]}}
  end

  def cast(_attrs, _networks, _accounts), do: {:error, %{base: ["a finding must be a map"]}}

  ## Field validation

  defp validate_trigger(changeset) do
    validate_change(changeset, :trigger, fn :trigger, id ->
      if Alerts.get_trigger_type(id), do: [], else: [trigger: "unknown trigger #{inspect(id)}"]
    end)
  end

  defp validate_evidence(changeset) do
    case get_field(changeset, :evidence) || [] do
      [] ->
        add_error(changeset, :evidence, "must contain at least one item")

      items ->
        case all_ok(items, &evidence/1) do
          {:ok, evidence} -> put_change(changeset, :evidence, evidence)
          {:error, message} -> add_error(changeset, :evidence, message)
        end
    end
  end

  defp validate_network(changeset, networks, accounts) do
    case {get_field(changeset, :network_id), get_field(changeset, :new_network)} do
      {nil, nil} ->
        add_error(changeset, :network_id, "give network_id or new_network")

      {id, nil} ->
        if Map.has_key?(networks, id) do
          validate_nested(changeset, :network_updates, &network_updates(&1, accounts))
        else
          add_error(changeset, :network_id, "unknown network #{inspect(id)}")
        end

      {nil, new} ->
        changeset =
          if get_field(changeset, :network_updates),
            do: add_error(changeset, :network_updates, "only apply to an existing network_id"),
            else: changeset

        case new_network(new, networks, accounts) do
          {:ok, network} -> put_change(changeset, :new_network, network)
          {:error, message} -> add_error(changeset, :new_network, message)
        end

      {_id, _new} ->
        add_error(changeset, :network_id, "give network_id or new_network, not both")
    end
  end

  defp validate_nested(changeset, field, normalize) do
    case get_field(changeset, field) do
      nil ->
        changeset

      value ->
        case normalize.(value) do
          {:ok, normalized} -> put_change(changeset, field, normalized)
          {:error, message} -> add_error(changeset, field, message)
        end
    end
  end

  ## Nested maps (atom or string keys)

  defp evidence(item) when is_map(item) do
    explanation = get(item, :explanation)
    account_ids = get(item, :account_ids) || []

    cond do
      not text?(explanation) ->
        {:error, "explanation can't be blank"}

      not Map.has_key?(@strengths, get(item, :strength)) ->
        {:error, "strength must be weak, moderate or strong"}

      not strings?(account_ids) ->
        {:error, "account_ids must be a list of strings"}

      true ->
        {:ok,
         %Evidence{
           explanation: explanation,
           strength: Map.fetch!(@strengths, get(item, :strength)),
           kind: Map.get(@kinds, get(item, :kind), :other),
           account_ids: account_ids
         }}
    end
  end

  defp evidence(_item), do: {:error, "each item must be a map"}

  defp new_network(new, networks, accounts) when is_map(new) do
    id = get(new, :id)
    member_ids = get(new, :member_ids)
    confidence = get(new, :confidence)
    platforms = get(new, :platforms) || []

    with :ok <- check(text?(id), "id can't be blank"),
         :ok <- check(not Map.has_key?(networks, id), "network #{inspect(id)} already exists"),
         :ok <- check(text?(get(new, :name)), "name can't be blank"),
         :ok <-
           check(
             strings?(member_ids) and member_ids != [],
             "member_ids must be a non-empty list of strings"
           ),
         :ok <-
           check(
             known?(member_ids, accounts),
             "unknown account #{inspect(unknown(member_ids, accounts))}"
           ),
         :ok <- check(percent?(confidence), "confidence must be an integer from 0 to 100"),
         :ok <- check(strings?(platforms), "platforms must be a list of strings"),
         :ok <- check(optional_text?(get(new, :main_domain)), "main_domain must be a string"),
         {:ok, summary} <- optional(get(new, :summary), &rationale/1),
         {:ok, evidence} <-
           optional(get(new, :evidence), &all_ok(&1, fn item -> evidence(item) end)) do
      {:ok,
       %{
         id: id,
         name: get(new, :name),
         member_ids: Enum.uniq(member_ids),
         confidence: confidence,
         platforms: platforms,
         main_domain: get(new, :main_domain),
         summary: summary,
         evidence: evidence || []
       }}
    end
  end

  defp new_network(_new, _networks, _accounts), do: {:error, "must be a map"}

  defp network_updates(updates, accounts) when is_map(updates) do
    add = get(updates, :add_member_ids) || []
    confidence = get(updates, :confidence)

    with :ok <- check(strings?(add), "add_member_ids must be a list of strings"),
         :ok <- check(known?(add, accounts), "unknown account #{inspect(unknown(add, accounts))}"),
         :ok <-
           check(
             is_nil(confidence) or percent?(confidence),
             "confidence must be an integer from 0 to 100"
           ),
         :ok <- check(optional_text?(get(updates, :main_domain)), "main_domain must be a string"),
         :ok <- check(optional_text?(get(updates, :name)), "name must be a string"),
         {:ok, summary} <- optional(get(updates, :summary), &rationale/1) do
      {:ok,
       %{
         add_member_ids: Enum.uniq(add),
         confidence: confidence,
         main_domain: get(updates, :main_domain),
         name: get(updates, :name),
         summary: summary
       }}
    end
  end

  defp network_updates(_updates, _accounts), do: {:error, "must be a map"}

  defp rationale(value) when is_map(value) do
    with :ok <- check(text?(get(value, :text)), "text can't be blank"),
         {:ok, at} <- datetime(get(value, :generated_at)) do
      {:ok, %{text: get(value, :text), generated_at: at}}
    end
  end

  defp rationale(_value), do: {:error, "must be a map with text and generated_at"}

  defp comparison(value) when is_map(value) do
    if Enum.all?([:label, :before, :after], &text?(get(value, &1))),
      do:
        {:ok,
         %{label: get(value, :label), before: get(value, :before), after: get(value, :after)}},
      else: {:error, "label, before and after must be non-empty strings"}
  end

  defp comparison(_value), do: {:error, "must be a map with label, before and after"}

  ## Helpers

  defp build(changeset) do
    fields = apply_changes(changeset)

    %__MODULE__{
      trigger_id: fields.trigger,
      severity: Map.fetch!(@severities, fields.severity),
      title: fields.title,
      observed_at: fields.observed_at,
      network_id: Map.get(fields, :network_id),
      new_network: Map.get(fields, :new_network),
      evidence: fields.evidence,
      ai_rationale: Map.get(fields, :ai_rationale),
      comparison: Map.get(fields, :comparison),
      network_updates: Map.get(fields, :network_updates)
    }
  end

  defp errors(changeset) do
    traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  # Reads a key given as an atom or its string form, without creating atoms.
  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

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

  defp all_ok(_items, _fun), do: {:error, "must be a list"}

  defp optional(nil, _fun), do: {:ok, nil}
  defp optional(value, fun), do: fun.(value)

  defp datetime(%DateTime{} = at), do: {:ok, DateTime.truncate(at, :second)}

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, DateTime.truncate(at, :second)}
      _error -> {:error, "generated_at must be an ISO 8601 date-time"}
    end
  end

  defp datetime(_value), do: {:error, "generated_at must be an ISO 8601 date-time"}

  defp check(true, _message), do: :ok
  defp check(false, message), do: {:error, message}

  defp text?(value), do: is_binary(value) and String.trim(value) != ""
  defp optional_text?(value), do: is_nil(value) or text?(value)
  defp strings?(value), do: is_list(value) and Enum.all?(value, &is_binary/1)
  defp percent?(value), do: is_integer(value) and value in 0..100

  # Unknown member ids are rejected at cast time so a later split never
  # crashes on `state.accounts[&1].feed_id`.
  defp known?(ids, accounts), do: Enum.all?(ids, &Map.has_key?(accounts, &1))

  defp unknown(ids, accounts), do: Enum.find(ids, &(not Map.has_key?(accounts, &1)))
end
