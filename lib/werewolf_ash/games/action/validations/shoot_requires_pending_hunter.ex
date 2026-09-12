defmodule WerewolfAsh.Games.Action.Validations.ShootRequiresPendingHunter do
  @moduledoc """
  Rejects a `:shoot` unless the actor holds the `:hunter` role and the
  actor's game is waiting on them (`state: :hunter_pending`) — rule 7.

  Per werewolf_ash-qss.4's own assumptions, this is the entire check: no
  liveness check (a hunter shoots after they are already dead) and no check
  on which phase the shot's `phase_id` names. Which player is "the" pending
  hunter is left to `hunter_pending` being a whole-game state paired with a
  game dealing exactly one hunter; a dedicated pointer, if one lands later,
  is werewolf_ash-qss.7's to consume.

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
    with {:ok, %{role: :hunter, game_id: game_id}} <-
           Games.get_player(actor_id, authorize?: false),
         {:ok, %{state: :hunter_pending}} <- Games.get_game(game_id, authorize?: false) do
      true
    else
      _ -> false
    end
  end
end
