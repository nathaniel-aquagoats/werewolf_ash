defmodule WerewolfAsh.Games.Game.RoleAssignment do
  @moduledoc """
  Pure role composition for a freshly started game.

  `composition/2` is only ever called once `start` has already confirmed the
  composition fits the actual seated count
  (`Validations.RoleCompositionFits`), so it enforces no minimum of its own —
  whatever `player_count` it is given, it deals exactly that many roles.
  """

  @doc """
  The multiset of roles to deal to `player_count` seated players, per
  `settings`: one of each special role enabled among `seer_enabled`,
  `bodyguard_enabled`, `hunter_enabled`; `manual_werewolf_count` werewolves
  when `settings.role_distribution_mode` is `:manual`, or
  `max(1, div(player_count, 4))` — qss.3's own formula — when `:automatic`;
  and the rest `:villager`. `settings` is anything exposing
  `role_distribution_mode`, `manual_werewolf_count`, `seer_enabled`,
  `bodyguard_enabled` and `hunter_enabled` (a `Game.t()` satisfies this).
  Returned as a flat list of roles, one per seat; the order carries no
  meaning — callers must not read a specific role into a specific position.
  """
  @spec composition(pos_integer, map) :: [atom]
  def composition(player_count, settings) when is_integer(player_count) do
    specials = specials(settings)
    wolves = werewolf_count(player_count, settings)
    villagers = player_count - length(specials) - wolves

    specials ++ List.duplicate(:werewolf, wolves) ++ List.duplicate(:villager, villagers)
  end

  defp specials(settings) do
    [
      {settings.seer_enabled, :seer},
      {settings.bodyguard_enabled, :bodyguard},
      {settings.hunter_enabled, :hunter}
    ]
    |> Enum.filter(fn {enabled, _role} -> enabled end)
    |> Enum.map(fn {_enabled, role} -> role end)
  end

  defp werewolf_count(_player_count, %{role_distribution_mode: :manual} = settings) do
    settings.manual_werewolf_count
  end

  defp werewolf_count(player_count, %{role_distribution_mode: :automatic}) do
    max(1, div(player_count, 4))
  end
end
