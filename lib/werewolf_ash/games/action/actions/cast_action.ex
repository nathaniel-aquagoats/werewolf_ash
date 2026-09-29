defmodule WerewolfAsh.Games.Action.Actions.CastAction do
  @moduledoc """
  Implements `Action`'s `:cast_vote`, `:cast_investigation`,
  `:cast_protection` and `:cast_shot` generic actions (rules 14-16, 18,
  werewolf_ash-27w.3): resolves the caller's own seat and the game's open
  phase (`CallerResolution`, rules 11-13), then calls
  `Games.create_action/5` with the `type` this instance is configured for
  (`:vote`, `:investigate`, `:protect` or `:shoot`), passing the caller as
  `actor` and the caller's own seat id as `actor_id`. No rule check is
  repeated here: every validation (aliveness, role, phase kind, the
  qss.21 upsert, the pending-hunter check, target-in-game) is
  `Games.create_action/5`'s own, and its errors come back unchanged.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.ActionInput
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.CallerResolution

  @impl true
  def run(input, opts, context) do
    type = Keyword.fetch!(opts, :type)
    game_id = ActionInput.get_argument(input, :game_id)
    target_id = ActionInput.get_argument(input, :target_id)
    actor = context.actor

    with {:ok, seat, phase} <- CallerResolution.resolve_seat_and_phase(game_id, actor) do
      Games.create_action(phase.id, seat.id, target_id, type, actor: actor)
    end
  end
end
