defmodule WerewolfAsh.Games.Game.Validations.CompositionFitsAtCap do
  @moduledoc """
  Rejects `:update_settings`, whenever the resulting `max_players` is set,
  when the enabled specials plus a wolves figure exceed `max_players` (rule
  7, `field: :max_players`). The wolves figure is `manual_werewolf_count`
  when the resulting `role_distribution_mode` is `:manual`, or
  `max(1, div(max_players, 4))` — `RoleAssignment`'s own formula, evaluated
  at the ceiling `max_players` — when the resulting mode is `:automatic`.
  When `max_players` is `nil` (no cap), this check does not apply to either
  mode; infeasibility is then only caught at start
  (`RoleCompositionFits`).

  An invalid `manual_werewolf_count` (`nil` or non-positive) is left to
  `ManualWerewolfCountValid` to reject on its own field; this validation adds
  no second error for it.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(changeset, _opts, _context) do
    case Changeset.get_attribute(changeset, :max_players) do
      nil ->
        :ok

      max_players ->
        check(changeset, max_players)
    end
  end

  defp check(changeset, max_players) do
    case wolves(changeset, max_players) do
      nil ->
        :ok

      wolves ->
        needed = specials(changeset) + wolves

        if needed <= max_players do
          :ok
        else
          {:error,
           field: :max_players,
           message: "too low for the enabled roles, which need at least %{needed} players",
           vars: [needed: needed]}
        end
    end
  end

  defp specials(changeset) do
    [
      Changeset.get_attribute(changeset, :seer_enabled),
      Changeset.get_attribute(changeset, :bodyguard_enabled),
      Changeset.get_attribute(changeset, :hunter_enabled)
    ]
    |> Enum.count(& &1)
  end

  defp wolves(changeset, max_players) do
    case Changeset.get_attribute(changeset, :role_distribution_mode) do
      :manual ->
        case Changeset.get_attribute(changeset, :manual_werewolf_count) do
          count when is_integer(count) and count >= 1 -> count
          _invalid -> nil
        end

      :automatic ->
        max(1, div(max_players, 4))

      # nil/invalid — left to role_distribution_mode's own allow_nil?/type
      # checks rather than raising here.
      _mode ->
        nil
    end
  end
end
