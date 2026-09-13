defmodule WerewolfAsh.Games.Game.Validations.RoleCompositionFits do
  @moduledoc """
  Rejects `start` when the roles `RoleAssignment.composition/2` would deal —
  the enabled specials plus the werewolf count, evaluated at the actual
  seated count for automatic mode — outnumber the players actually seated.
  Equal is allowed: zero villagers is a valid, if grim, game.
  """

  use Ash.Resource.Validation

  alias WerewolfAsh.Games

  @impl true
  def validate(changeset, _opts, _context) do
    game = changeset.data

    seated =
      Games.list_players!(query: [filter: [game_id: game.id]], authorize?: false)
      |> length()

    needed = specials_count(game) + werewolf_count(seated, game)

    if needed <= seated do
      :ok
    else
      {:error,
       field: :players,
       message: "needs at least %{needed} seated players for its role settings, has %{seated}",
       vars: [needed: needed, seated: seated]}
    end
  end

  defp specials_count(game) do
    [game.seer_enabled, game.bodyguard_enabled, game.hunter_enabled]
    |> Enum.count(& &1)
  end

  defp werewolf_count(_seated, %{role_distribution_mode: :manual, manual_werewolf_count: count}) do
    count
  end

  defp werewolf_count(seated, %{role_distribution_mode: :automatic}) do
    max(1, div(seated, 4))
  end
end
