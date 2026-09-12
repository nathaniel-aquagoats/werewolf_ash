defmodule WerewolfAsh.Games.Game.Changes.DealRoles do
  @moduledoc """
  Deals exactly one role to every player already seated in a game, once
  `start` has passed its actor and minimum-player checks.

  Queues an `after_action` hook (alongside `AdvancePhase`'s own hook that
  opens the first phase) so the roles are dealt once the game row itself has
  successfully left the lobby. `RoleAssignment.composition/1` computes the
  counts; which seat gets which role is unspecified beyond that.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Ash.Context
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Game.RoleAssignment

  @impl true
  def change(changeset, _opts, context) do
    Changeset.after_action(changeset, fn _changeset, game ->
      deal(game, Context.to_opts(context))
    end)
  end

  defp deal(game, opts) do
    players = Games.list_players!(query: [filter: [game_id: game.id]])
    roles = Enum.shuffle(RoleAssignment.composition(length(players)))

    players
    |> Enum.zip(roles)
    |> Enum.reduce_while({:ok, game}, fn {player, role}, {:ok, game} ->
      case Games.update_player(player, %{role: role}, opts) do
        {:ok, _player} -> {:cont, {:ok, game}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
