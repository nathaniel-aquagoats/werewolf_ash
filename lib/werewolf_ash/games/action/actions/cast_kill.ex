defmodule WerewolfAsh.Games.Action.Actions.CastKill do
  @moduledoc """
  Implements `Action`'s `:cast_kill` generic action (rules 14-16, 18,
  werewolf_ash-27w.3): resolves the caller's own seat and the game's open
  phase (`CallerResolution`, rules 11-13), then calls
  `Games.create_kill_action/4` as the caller with the caller's own seat id
  as `actor_id`. No rule check is repeated here: `Games.create_kill_action/4`
  is the one place the pack's kill is validated (aliveness, role, phase
  kind, the one-kill-per-phase identity, target-in-game), and its errors
  come back unchanged.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.ActionInput
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.CallerResolution

  @impl true
  def run(input, _opts, context) do
    game_id = ActionInput.get_argument(input, :game_id)
    target_id = ActionInput.get_argument(input, :target_id)
    actor = context.actor

    with {:ok, seat, phase} <- CallerResolution.resolve_seat_and_phase(game_id, actor) do
      Games.create_kill_action(phase.id, seat.id, target_id, actor: actor)
    end
  end
end
