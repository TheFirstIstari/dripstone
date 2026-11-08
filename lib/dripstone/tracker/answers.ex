defmodule Dripstone.Tracker.Answers do
  @moduledoc """
  Reads the decision model's answers map (Jev via `Dripstone.AIClient.decide/3`),
  exactly as returned, into one normalized shape per answer:

    * `noul`: `%{type: :noul, value: p}`, the probability of yes (0–1).
    * `choice`: `%{type: :choice, label: "shared-link", confidence: c | nil,
      probabilities: map | nil}`.
    * `score`: `%{type: :score, value: v, score: s, levels: n, legend: map | nil,
      confidence: c | nil}`, where `score` is Jev's expected level (0..n-1) and
      `value` is `score / (n - 1)`, normalized to 0–1. The number of levels comes
      from `legend` or `probabilities`, or from the app's known questions.
    * any other type: `%{type: :other, raw: answer}`, kept for display only.

  Answer and question names stay strings. Answers to questions the app does not use
  are kept and never interpreted. Keys may be atoms or strings, so both decoded
  JSON and Elixir maps work.
  """

  # Score questions the app asks, with their number of levels, used when an answer
  # carries neither `legend` nor `probabilities`.
  @known_levels %{"spam" => 3}

  @relations %{
    "repost-ring" => :repost_ring,
    "shared-link" => :shared_link,
    "timing-sync" => :timing_sync,
    "audience-overlap" => :audience_overlap,
    "none" => :none
  }

  @type parsed :: %{String.t() => map()}

  @doc "The relation labels the app understands, mapped to link kinds."
  @spec relations() :: %{String.t() => atom()}
  def relations, do: @relations

  @doc """
  Parses an answers map. Returns `{:ok, nil}` for `nil` (AI unavailable),
  `{:ok, parsed}`, or `{:error, message}` naming the first malformed answer.
  """
  @spec parse(term()) :: {:ok, parsed() | nil} | {:error, String.t()}
  def parse(nil), do: {:ok, nil}

  def parse(answers) when is_map(answers) and map_size(answers) > 64 do
    {:error, "must have at most 64 answers"}
  end

  def parse(answers) when is_map(answers) do
    answers
    |> Enum.sort_by(fn {name, _} -> to_string(name) end)
    |> Enum.reduce_while({:ok, %{}}, fn {name, answer}, {:ok, acc} ->
      name = to_string(name)

      case parse_answer(name, answer) do
        {:ok, parsed} -> {:cont, {:ok, Map.put(acc, name, parsed)}}
        {:error, message} -> {:halt, {:error, "#{name}: #{message}"}}
      end
    end)
  end

  def parse(_answers), do: {:error, "must be a map of answers or null"}

  defp parse_answer(_name, answer) when not is_map(answer), do: {:error, "must be a map"}

  defp parse_answer(name, answer) do
    case get(answer, :type) do
      type when type in ["noul", :noul] ->
        noul_answer(answer)

      type when type in ["choice", :choice] ->
        choice_answer(answer)

      type when type in ["score", :score] ->
        score_answer(name, answer)

      type when is_binary(type) or (is_atom(type) and not is_nil(type)) ->
        {:ok, %{type: :other, raw: answer}}

      _ ->
        {:error, "type is missing"}
    end
  end

  defp noul_answer(answer) do
    case get(answer, :noul) do
      p when is_number(p) and p >= 0 and p <= 1 -> {:ok, %{type: :noul, value: p / 1}}
      _ -> {:error, "noul must be a number from 0 to 1"}
    end
  end

  defp choice_answer(answer) do
    with label when is_binary(label) and label != "" <- get(answer, :choice),
         {:ok, confidence} <- fraction(get(answer, :confidence)) do
      {:ok,
       %{
         type: :choice,
         label: label,
         confidence: confidence,
         probabilities: map_or_nil(get(answer, :probabilities))
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, "choice must be a non-empty string"}
    end
  end

  defp score_answer(name, answer) do
    legend = map_or_nil(get(answer, :legend))
    probabilities = map_or_nil(get(answer, :probabilities))
    levels = levels(legend, probabilities, Map.get(@known_levels, name))

    with score when is_number(score) and score >= 0 <- get(answer, :score),
         {:ok, levels} <- levels,
         true <- score <= levels - 1 || {:error, "score is above the highest level"},
         {:ok, confidence} <- fraction(get(answer, :confidence)) do
      {:ok,
       %{
         type: :score,
         value: score / (levels - 1),
         score: score,
         levels: levels,
         legend: legend,
         confidence: confidence
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, "score must be a number of at least 0"}
    end
  end

  defp levels(legend, _probabilities, _known) when is_map(legend) and map_size(legend) >= 2,
    do: {:ok, map_size(legend)}

  defp levels(_legend, probs, _known) when is_map(probs) and map_size(probs) >= 2,
    do: {:ok, map_size(probs)}

  defp levels(_legend, _probabilities, known) when is_integer(known), do: {:ok, known}

  defp levels(_legend, _probabilities, _known),
    do: {:error, "has no legend or probabilities to tell how many levels it has"}

  defp fraction(nil), do: {:ok, nil}
  defp fraction(c) when is_number(c) and c >= 0 and c <= 1, do: {:ok, c / 1}
  defp fraction(_), do: {:error, "confidence must be a number from 0 to 1"}

  defp map_or_nil(value) when is_map(value), do: value
  defp map_or_nil(_), do: nil

  ## Reading parsed answers

  @doc "The probability of a `noul` answer, or nil if absent or of another type."
  @spec noul(parsed() | nil, String.t()) :: float() | nil
  def noul(answers, name) do
    case answers && answers[name] do
      %{type: :noul, value: p} -> p
      _ -> nil
    end
  end

  @doc "`{label, confidence}` of a `choice` answer, or nil."
  @spec choice(parsed() | nil, String.t()) :: {String.t(), float() | nil} | nil
  def choice(answers, name) do
    case answers && answers[name] do
      %{type: :choice, label: label, confidence: confidence} -> {label, confidence}
      _ -> nil
    end
  end

  @doc "The normalized 0–1 value of a `score` answer, or nil."
  @spec score(parsed() | nil, String.t()) :: float() | nil
  def score(answers, name) do
    case answers && answers[name] do
      %{type: :score, value: value} -> value
      _ -> nil
    end
  end

  @doc """
  The `relation` answer as `{kind, label, confidence}`, where `kind` is a link kind
  atom or `:none`. An unknown label gives nil.
  """
  @spec relation(parsed() | nil) :: {atom(), String.t(), float() | nil} | nil
  def relation(answers) do
    with {label, confidence} <- choice(answers, "relation"),
         {:ok, kind} <- Map.fetch(@relations, label) do
      {kind, label, confidence}
    else
      _ -> nil
    end
  end

  @doc """
  A short display value for one parsed answer: `"81%"` for a `noul`, the label (with
  confidence) for a `choice`, the legend level for a `score`.
  """
  @spec display(map()) :: String.t()
  def display(%{type: :noul, value: p}), do: percent(p)

  def display(%{type: :choice, label: label, confidence: nil}), do: label
  def display(%{type: :choice, label: label, confidence: c}), do: "#{label} (#{percent(c)})"

  def display(%{type: :score, score: score, levels: levels, legend: legend}) do
    level = legend && Map.get(legend, to_string(round(score)))
    of = "#{format_number(score)} of #{levels - 1}"
    if is_binary(level), do: "#{level} (#{of})", else: of
  end

  def display(%{type: :other, raw: raw}), do: inspect(raw, limit: 5, printable_limit: 80)

  @doc "Formats a 0–1 fraction as a whole percentage, e.g. `\"81%\"`."
  @spec percent(number()) :: String.t()
  def percent(p), do: "#{round(p * 100)}%"

  defp format_number(n) when is_integer(n), do: Integer.to_string(n)
  defp format_number(n), do: n |> Float.round(2) |> Float.to_string()

  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
