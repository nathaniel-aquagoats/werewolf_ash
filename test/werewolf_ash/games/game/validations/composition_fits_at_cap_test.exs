defmodule WerewolfAsh.Games.Game.Validations.CompositionFitsAtCapTest do
  use ExUnit.Case, async: true

  alias Ash.Changeset
  alias WerewolfAsh.Games.Game
  alias WerewolfAsh.Games.Game.Validations.CompositionFitsAtCap

  defp changeset(attrs) do
    Changeset.new(
      struct(
        Game,
        Keyword.merge(
          [
            role_distribution_mode: :automatic,
            manual_werewolf_count: nil,
            seer_enabled: true,
            bodyguard_enabled: true,
            hunter_enabled: true,
            max_players: nil
          ],
          attrs
        )
      )
    )
  end

  describe "validate/3" do
    test "a nil max_players never has a ceiling to fail against" do
      assert CompositionFitsAtCap.validate(changeset(max_players: nil), [], %{}) == :ok
    end

    test "automatic mode: passes when specials plus wolves(max_players) fits" do
      assert CompositionFitsAtCap.validate(changeset(max_players: 4), [], %{}) == :ok
    end

    test "automatic mode: fails, on :max_players, when specials plus wolves(max_players) overflow" do
      assert {:error, error} = CompositionFitsAtCap.validate(changeset(max_players: 3), [], %{})
      assert Keyword.fetch!(error, :field) == :max_players
    end

    test "manual mode: passes when specials plus the configured count fits max_players" do
      changeset =
        changeset(role_distribution_mode: :manual, manual_werewolf_count: 2, max_players: 5)

      assert CompositionFitsAtCap.validate(changeset, [], %{}) == :ok
    end

    test "manual mode: fails, on :max_players, when specials plus the configured count overflow" do
      changeset =
        changeset(role_distribution_mode: :manual, manual_werewolf_count: 3, max_players: 4)

      assert {:error, error} = CompositionFitsAtCap.validate(changeset, [], %{})
      assert Keyword.fetch!(error, :field) == :max_players
    end
  end
end
