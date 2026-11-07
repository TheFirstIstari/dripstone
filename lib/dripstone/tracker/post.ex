defmodule Dripstone.Tracker.Post do
  @moduledoc """
  A post by a tracked account. `post_id` is the platform's own id, used with the
  feed to build a link; `domain` is the promoted domain, if the post links out.
  """

  @enforce_keys [:id, :account_id, :post_id, :posted_at]
  defstruct [:id, :account_id, :post_id, :posted_at, :text, :domain]

  @type t :: %__MODULE__{
          id: String.t(),
          account_id: String.t(),
          post_id: String.t(),
          posted_at: DateTime.t(),
          text: String.t() | nil,
          domain: String.t() | nil
        }
end
