defmodule WerewolfAsh.Games.Game.Validations.MinNotAboveMax do
  @moduledoc """
  Rejects `:update_settings` when the resulting `min_players` is greater than
  the resulting `max_players`, when `max_players` is set (rule 5,
  `field: :max_players`); a `nil` `max_players` never conflicts with
  `min_players`.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(changeset, _opts, _context) do
    min_players = Changeset.get_attribute(changeset, :min_players)

    case Changeset.get_attribute(changeset, :max_players) do
      nil ->
        :ok

      max_players when min_players > max_players ->
        {:error,
         field: :max_players,
         message: "must be at least min_players (%{min_players})",
         vars: [min_players: min_players]}

      _max_players ->
        :ok
    end
  end
end
