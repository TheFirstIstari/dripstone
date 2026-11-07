defmodule Dripstone.AIClient do
  @moduledoc """
  Client for the OpenCode Console decision endpoint (Jev, TypeSafe AI).

  `decide/3` POSTs `{model, state, questions}` to `{base}/systemone` with
  bearer auth and returns `{:ok, answers}` on a 200 response carrying an
  answers map. Any error, non-200, or bad shape logs a warning and returns
  `{:error, reason}` — callers fall back to heuristics-only, never to fake
  answers.

  Calling-context contract: `decide/3` blocks synchronously up to ~35s
  worst-case (30s receive timeout + 5s connect timeout). Allowed callers are
  Oban workers or supervised Tasks with their own timeout — callers own
  retry/idempotency since the client sets `retry: false`. FORBIDDEN in
  LiveView callbacks and request processes.
  """

  require Logger

  @state_cap 8_000
  @max_questions 32

  def decide(state, questions, opts \\ []) do
    try do
      conf = Application.get_env(:dripstone, __MODULE__, [])

      base_raw = Keyword.get(conf, :base_url, "https://opencode.ai/inference/systemone/v1")
      model = Keyword.get(opts, :model, Keyword.get(conf, :model, "jev-1.13-free"))
      api_key = Keyword.get(conf, :api_key)

      cond do
        not (is_binary(api_key) and api_key != "") ->
          Logger.warning("AIClient missing api key — refusing unauthenticated request")
          {:error, :missing_api_key}

        not is_binary(state) ->
          {:error, {:invalid_args, "state must be a binary"}}

        not is_map(questions) ->
          {:error, {:invalid_args, "questions must be a map"}}

        map_size(questions) > @max_questions ->
          {:error, {:invalid_args, "questions must have at most #{@max_questions} entries"}}

        not is_binary(base_raw) ->
          {:error, {:invalid_args, "base_url must be a binary"}}

        true ->
          base = String.trim_trailing(base_raw, "/")

          req_opts =
            [
              json: %{
                "model" => model,
                "state" => truncate(state),
                "questions" => questions
              },
              headers: auth_headers(api_key),
              receive_timeout: 30_000,
              connect_options: [timeout: 5_000],
              retry: false
            ]
            # :plug is test-only (Req.Test stub) — must never be forwarded from user input.
            |> Keyword.merge(Keyword.take(opts, [:plug]))

          started_at = System.monotonic_time(:millisecond)

          result =
            case Req.post(base <> "/systemone", req_opts) do
              {:ok, %{status: 200, body: %{"answers" => answers}}} when is_map(answers) ->
                {:ok, answers}

              {:ok, %{status: 200, body: body}} ->
                Logger.warning(
                  "AIClient bad response shape: #{inspect(body, limit: 5, printable_limit: 200)}"
                )

                {:error, :bad_response}

              {:ok, %{status: status, body: body}} ->
                Logger.warning(
                  "AIClient HTTP #{status}: #{inspect(body, limit: 5, printable_limit: 200)}"
                )

                {:error, {:http_error, status}}

              {:error, reason} ->
                Logger.warning(
                  "AIClient transport error: #{inspect(reason, limit: 5, printable_limit: 200)}"
                )

                {:error, {:transport, reason}}
            end

          Logger.debug(
            "AIClient decide model=#{inspect(model)} latency_ms=#{latency_ms(started_at)}"
          )

          result
      end
    rescue
      e ->
        Logger.warning("AIClient exception: #{Exception.message(e)}")
        {:error, {:transport, e}}
    end
  end

  defp truncate(state) when is_binary(state), do: String.slice(state, 0, @state_cap)

  defp auth_headers(api_key) when is_binary(api_key) and api_key != "",
    do: [{"authorization", "Bearer #{api_key}"}]

  defp latency_ms(started_at), do: System.monotonic_time(:millisecond) - started_at
end
