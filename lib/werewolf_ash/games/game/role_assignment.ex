defmodule WerewolfAsh.Games.Game.RoleAssignment do
  @moduledoc """
  Pure role composition for a freshly started game.

  `composition/1` is only ever called once `start` has already confirmed at
  least 5 seated players (`Validations.MinimumPlayers`), so its contract is
  defined only for `player_count >= 5`.
  """

  @special [:seer, :bodyguard, :hunter]

  @doc """
  The multiset of roles to deal to `player_count` seated players: exactly one
  `:seer`, one `:bodyguard`, one `:hunter`, `max(1, div(player_count, 4))`
  `:werewolf`(s), and the rest `:villager`. Returned as a flat list of roles,
  one per seat; the order carries no meaning — callers must not read a
  specific role into a specific position.
  """
  @spec composition(pos_integer) :: [atom]
  def composition(player_count) when is_integer(player_count) and player_count >= 5 do
    wolves = max(1, div(player_count, 4))
    villagers = player_count - length(@special) - wolves

    @special ++ List.duplicate(:werewolf, wolves) ++ List.duplicate(:villager, villagers)
  end
end
