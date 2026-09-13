defmodule WerewolfAsh.Games.Game.Validations.PositivePlayerBounds do
  @moduledoc """
  Rejects `:update_settings` when the resulting `min_players` is not
  positive (rule 4, `field: :min_players`), or when a supplied
  `max_players` is not positive (rule 4, `field: :max_players`); a `nil`
  `max_players` is never subject to this check.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(changeset, _opts, _context) do
    min_players = Changeset.get_attribute(changeset, :min_players)
    max_players = Changeset.get_attribute(changeset, :max_players)

    cond do
      is_integer(min_players) and min_players < 1 ->
        {:error, field: :min_players, message: "must be at least 1"}

      is_integer(max_players) and max_players < 1 ->
        {:error, field: :max_players, message: "must be at least 1"}

      true ->
        :ok
    end
  end
end
