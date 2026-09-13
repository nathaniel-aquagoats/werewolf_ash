defmodule WerewolfAsh.Games.Game.Validations.ManualWerewolfCountValid do
  @moduledoc """
  Rejects `:update_settings` when the resulting `manual_werewolf_count` is
  `nil` or less than 1, whenever the resulting `role_distribution_mode` is
  `:manual` (rule 6, `field: :manual_werewolf_count`). The same nil/low
  value is accepted when the resulting mode is `:automatic`, since it is
  never read there.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(changeset, _opts, _context) do
    case Changeset.get_attribute(changeset, :role_distribution_mode) do
      :manual ->
        check(Changeset.get_attribute(changeset, :manual_werewolf_count))

      # :automatic, or nil/invalid — the latter is left to role_distribution_mode's
      # own allow_nil?/type checks rather than raising here.
      _mode ->
        :ok
    end
  end

  defp check(count) when is_integer(count) and count >= 1, do: :ok

  defp check(_count) do
    {:error,
     field: :manual_werewolf_count,
     message: "must be at least 1 when role_distribution_mode is manual"}
  end
end
