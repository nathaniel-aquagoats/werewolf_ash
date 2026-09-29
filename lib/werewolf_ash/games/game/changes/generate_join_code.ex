defmodule WerewolfAsh.Games.Game.Changes.GenerateJoinCode do
  @moduledoc """
  Sets `:join_code` on `Game`'s `:open` create action (rules 22-23,
  werewolf_ash-27w.3). Draws candidates of 6 uppercase characters from the
  look-alike-free alphabet `ABCDEFGHJKMNPQRSTUVWXYZ23456789` and takes the
  first that matches no existing game
  (`Games.get_game_by_join_code/2`, `authorize?: false` - the same lookup
  `ResolveGameByJoinCode` already uses to resolve a join code, never an
  access check in its own right).

  Candidates come from `changeset.context[:join_code_candidates]` when that
  is a list, consumed in order (for tests, via
  `Games.open_game(params, context: %{join_code_candidates: [...]})`);
  otherwise 10 candidates are drawn with `Enum.random/1`. Once every
  candidate is taken, the changeset fails on `:join_code`; the residual race
  between this check and the insert is left to the `unique_join_code`
  identity's own error.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @alphabet ~w(A B C D E F G H J K M N P Q R S T U V W X Y Z 2 3 4 5 6 7 8 9)
  @length 6
  @attempts 10

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> candidates()
    |> Enum.find(&available?/1)
    |> case do
      nil ->
        Changeset.add_error(changeset,
          field: :join_code,
          message: "could not generate a unique join code"
        )

      code ->
        Changeset.force_change_attribute(changeset, :join_code, code)
    end
  end

  defp candidates(changeset) do
    case changeset.context[:join_code_candidates] do
      list when is_list(list) -> Enum.take(list, @attempts)
      _ -> Enum.map(1..@attempts, fn _ -> random_code() end)
    end
  end

  defp available?(code) do
    case Games.get_game_by_join_code(code, authorize?: false) do
      {:ok, _game} -> false
      {:error, _error} -> true
    end
  end

  @doc "A random 6-character code drawn from the look-alike-free alphabet."
  @spec random_code() :: String.t()
  def random_code do
    Enum.map_join(1..@length, "", fn _ -> Enum.random(@alphabet) end)
  end
end
