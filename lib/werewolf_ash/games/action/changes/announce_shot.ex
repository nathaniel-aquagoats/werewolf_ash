defmodule WerewolfAsh.Games.Action.Changes.AnnounceShot do
  @moduledoc """
  Announces a landed `:shoot` at once, in the shot's own transaction: one
  `shot` announcement listing only the shot player, stamped with the wall
  clock. Registered after `ApplyShot`, for `:shoot` only; a refused shot never
  reaches its `after_action`.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Announcer

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.after_action(changeset, fn _changeset, action ->
      with {:ok, target} <- Games.get_player(action.target_id, authorize?: false),
           {:ok, _} <-
             Announcer.announce(target.game_id, :shot, DateTime.utc_now(), %{
               deaths: [%{player_id: target.id, role: target.role, cause: :shot}]
             }) do
        {:ok, action}
      end
    end)
  end
end
