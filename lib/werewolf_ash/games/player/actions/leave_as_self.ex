defmodule WerewolfAsh.Games.Player.Actions.LeaveAsSelf do
  @moduledoc """
  Implements `Player`'s `:leave_as_self` generic action (rule 25,
  werewolf_ash-27w.3): resolves the caller's own seat in the named game
  (`CallerResolution`, rules 11, 12 - the open-phase part of rule 13 does
  not apply, a lobby has none), then calls `Games.remove_player/2` on that
  seat as the caller, so the existing `GameInLobby` validation refuses
  leaving once the game has started or finished. `OwnerCannotLeave` (rule
  26) refuses the owner's own attempt before this ever runs.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.ActionInput
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.CallerResolution

  @impl true
  def run(input, _opts, context) do
    actor = context.actor
    game_id = ActionInput.get_argument(input, :game_id)

    with {:ok, seat} <- CallerResolution.resolve_seat(game_id, actor) do
      Games.remove_player(seat, actor: actor)
    end
  end
end
