defmodule WerewolfAsh.Games.Player.Actions.JoinAsSelf do
  @moduledoc """
  Implements `Player`'s `:join_as_self` generic action (rule 24,
  werewolf_ash-27w.3): upcases the given `join_code`
  (case-insensitive, owner decision 8), then calls `Games.join_game/3` with
  the caller's own id as `user_id` - the same value
  `set_attribute(:user_id, actor(:id))` would give, never a client input -
  and the caller as `actor`, so `:join`'s own rules
  (`GameInLobby`, `UserHasName`, `GameNotFull`, the unknown-code error and
  the unique seat) all apply unchanged.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.ActionInput
  alias WerewolfAsh.Games

  @impl true
  def run(input, _opts, context) do
    actor = context.actor
    join_code = input |> ActionInput.get_argument(:join_code) |> String.upcase()

    Games.join_game(join_code, actor.id, actor: actor)
  end
end
