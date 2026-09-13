defmodule WerewolfAsh.Games.Game.Validations.MinNotAboveMaxTest do
  use ExUnit.Case, async: true

  alias Ash.Changeset
  alias WerewolfAsh.Games.Game
  alias WerewolfAsh.Games.Game.Validations.MinNotAboveMax

  defp changeset(min_players, max_players) do
    Changeset.new(%Game{min_players: min_players, max_players: max_players})
  end

  describe "validate/3" do
    test "passes when min_players is at or below a set max_players" do
      assert MinNotAboveMax.validate(changeset(5, 10), [], %{}) == :ok
      assert MinNotAboveMax.validate(changeset(5, 5), [], %{}) == :ok
    end

    test "a nil max_players never conflicts with min_players" do
      assert MinNotAboveMax.validate(changeset(50, nil), [], %{}) == :ok
    end

    test "fails, on :max_players, when min_players exceeds a set max_players" do
      assert {:error, error} = MinNotAboveMax.validate(changeset(10, 5), [], %{})
      assert Keyword.fetch!(error, :field) == :max_players
    end
  end
end
