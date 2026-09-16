defmodule WerewolfAsh.Games.Action.Checks.WithdrawNamesOwnSeat do
  @moduledoc """
  Rule 11 — the "actor's own seat only" policy for `:withdraw`, checked
  differently than `:create`/`:kill` because `:withdraw` is a generic
  action with no row to traverse a `relates_to_actor_via`/
  `expr(exists(actor, ...))`-style check against. Instead this reads the
  `:actor_id` *argument* directly off the in-flight
  `Ash.Policy.Authorizer.t()`'s `action_input` field and looks up the
  `Player` it names: forbidden unless that player's `user_id` matches the
  calling actor's `id`. Anyone else's `actor_id`, or no actor at all, is
  forbidden.

  Loads the `Player` unauthorized (`authorize?: false`), matching
  `ActorAlive`'s stated reasoning: this is a game rule (whose seat is
  named), not an access check in its own right — the access check is this
  very policy.
  """

  use Ash.Policy.SimpleCheck

  alias Ash.ActionInput
  alias WerewolfAsh.Games

  @impl true
  def describe(_opts), do: "actor_id names the calling actor's own seat"

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, %{action_input: %ActionInput{} = action_input}, _opts) do
    with actor_id when not is_nil(actor_id) <-
           ActionInput.get_argument(action_input, :actor_id),
         {:ok, %{user_id: user_id}} <- Games.get_player(actor_id, authorize?: false) do
      user_id == actor.id
    else
      _ -> false
    end
  end

  def match?(_actor, _context, _opts), do: false
end
