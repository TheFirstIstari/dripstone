defmodule Dripstone.Tracker.Link do
  @moduledoc """
  An undirected link between two accounts, e.g. both posting near-duplicate text.
  `account_ids` is a sorted pair so each link is stored once.
  """

  @kinds [:shared_link, :near_duplicate, :synced_posting, :created_together]
  @strengths [:weak, :moderate, :strong]

  @enforce_keys [:account_ids, :kind, :strength]
  defstruct [:account_ids, :kind, :strength]

  @type kind :: :shared_link | :near_duplicate | :synced_posting | :created_together
  @type t :: %__MODULE__{
          account_ids: {String.t(), String.t()},
          kind: kind(),
          strength: :weak | :moderate | :strong
        }

  @doc "All link kinds, in legend order."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc "All strengths, weakest first."
  @spec strengths() :: [atom()]
  def strengths, do: @strengths
end
