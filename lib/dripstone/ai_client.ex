defmodule Dripstone.AIClient do
  @moduledoc """
  Minimal client for the internal OpenAI-compatible chat endpoint
  (vLLM on the `desktop` host). Any error or non-200 falls back to
  a mock reply so dev/test/CI never depend on the GPU box.
  """

  def complete(prompt, opts \\ []) do
    base = System.get_env("INTERNAL_AI_URL", "http://desktop:8000/v1")
    model = Keyword.get(opts, :model, System.get_env("INTERNAL_AI_MODEL", "Qwen/Qwen3-8B-AWQ"))

    body = %{
      "model" => model,
      "messages" => [%{"role" => "user", "content" => prompt}]
    }

    case Req.post("#{base}/chat/completions",
           json: body,
           receive_timeout: 30_000,
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        {:ok, content}

      _ ->
        {:ok, "[mock] #{prompt}"}
    end
  rescue
    _ -> {:ok, "[mock] #{prompt}"}
  end
end
