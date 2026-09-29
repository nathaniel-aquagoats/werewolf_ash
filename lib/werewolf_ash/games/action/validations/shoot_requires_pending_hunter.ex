defmodule WerewolfAsh.Games.Action.Validations.ShootRequiresPendingHunter do
  @moduledoc """
  Rejects a `:shoot` unless the actor's own player id is the game's
  `pending_hunter_id` (rule 10) - the game being the one the actor is
  seated in. Reads neither `Game.state` nor the actor's role: which player
  may shoot is entirely the pointer's own business now that the window is a
  pointer, not a whole-game state (werewolf_ash-qss.7).

  Fails, on `:actor_id`, when the pointer is nil, names someone else, or the
  actor is not a player at all.

  Loads `Player`/`Game` unauthorized (`authorize?: false`), matching
  `AuthorMayPost`'s stated reasoning: this is a game rule, not an access
  check.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @impl true
  def validate(changeset, _opts, _context) do
    case Changeset.get_attribute(changeset, :actor_id) do
      nil ->
        :ok

      actor_id ->
        if pending_hunter?(actor_id) do
          :ok
        else
          {:error, field: :actor_id, message: "only the game's pending hunter may shoot"}
        end
    end
  end

  defp pending_hunter?(actor_id) do
    with {:ok, %{game_id: game_id}} <- Games.get_player(actor_id, authorize?: false),
         {:ok, %{pending_hunter_id: ^actor_id}} <- Games.get_game(game_id, authorize?: false) do
      true
    else
      _ -> false
    end
  end
end
