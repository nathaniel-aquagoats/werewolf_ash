defmodule WerewolfAsh.Games.Game.Changes.AnnounceGameOver do
  @moduledoc """
  On `:finish`, announces the winner, in the same transaction, whichever route
  finished the game. Lists no deaths and reveals no role of its own: a finished
  game's roles are already visible through the `Player.role` policy.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias WerewolfAsh.Games.Announcer

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.after_action(changeset, fn _changeset, game ->
      with {:ok, _} <-
             Announcer.announce(game.id, :game_over, DateTime.utc_now(), %{winner: game.winner}) do
        {:ok, game}
      end
    end)
  end
end
