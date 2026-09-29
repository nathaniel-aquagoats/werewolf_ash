defmodule WerewolfAsh.Games.Player.Validations.OwnerCannotLeave do
  @moduledoc """
  Rejects `Player`'s `:leave_as_self` generic action when the calling actor
  is the named game's own owner (rule 26, werewolf_ash-27w.3): the seat
  stays, and the failure lands on `:game_id`.

  Reads the `game_id` argument off the in-flight `Ash.ActionInput`, matching
  `WithdrawNamesOwnSeat`'s shape for a generic action with no row of its own
  to traverse. Loads the `Game` unauthorized (`authorize?: false`), matching
  `ShootRequiresPendingHunter`'s stated reasoning: this is a game rule (who
  owns the game), not an access check in its own right.
  """

  use Ash.Resource.Validation

  alias Ash.ActionInput
  alias WerewolfAsh.Games

  @impl true
  def supports(_opts), do: [Ash.ActionInput]

  @impl true
  def validate(%ActionInput{} = input, _opts, context) do
    with game_id when not is_nil(game_id) <- ActionInput.get_argument(input, :game_id),
         actor when not is_nil(actor) <- context.actor,
         {:ok, %{owner_id: owner_id}} <- Games.get_game(game_id, authorize?: false),
         true <- owner_id == actor.id do
      {:error, field: :game_id, message: "the owner cannot leave their own game"}
    else
      _ -> :ok
    end
  end
end
