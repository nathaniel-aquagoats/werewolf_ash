defmodule WerewolfAsh.Games.Game.Validations.PositivePlayerBoundsTest do
  use ExUnit.Case, async: true

  alias Ash.Changeset
  alias WerewolfAsh.Games.Game
  alias WerewolfAsh.Games.Game.Validations.PositivePlayerBounds

  defp changeset(min_players, max_players) do
    Changeset.new(%Game{min_players: min_players, max_players: max_players})
  end

  describe "validate/3" do
    test "passes with a positive min_players and no max_players" do
      assert PositivePlayerBounds.validate(changeset(1, nil), [], %{}) == :ok
    end

    test "fails, on :min_players, when min_players is not positive" do
      assert {:error, error} = PositivePlayerBounds.validate(changeset(0, nil), [], %{})
      assert Keyword.fetch!(error, :field) == :min_players
    end

    test "fails, on :max_players, when a supplied max_players is not positive" do
      assert {:error, error} = PositivePlayerBounds.validate(changeset(5, 0), [], %{})
      assert Keyword.fetch!(error, :field) == :max_players
    end

    test "a nil max_players is never subject to this check" do
      assert PositivePlayerBounds.validate(changeset(5, nil), [], %{}) == :ok
    end
  end
end
