defmodule WerewolfAsh.Games.Game.Validations.ManualWerewolfCountValidTest do
  use ExUnit.Case, async: true

  alias Ash.Changeset
  alias WerewolfAsh.Games.Game
  alias WerewolfAsh.Games.Game.Validations.ManualWerewolfCountValid

  defp changeset(mode, count) do
    Changeset.new(%Game{role_distribution_mode: mode, manual_werewolf_count: count})
  end

  describe "validate/3" do
    test "passes with a positive count in manual mode" do
      assert ManualWerewolfCountValid.validate(changeset(:manual, 1), [], %{}) == :ok
    end

    test "fails, on :manual_werewolf_count, when nil in manual mode" do
      assert {:error, error} = ManualWerewolfCountValid.validate(changeset(:manual, nil), [], %{})
      assert Keyword.fetch!(error, :field) == :manual_werewolf_count
    end

    test "fails, on :manual_werewolf_count, when less than 1 in manual mode" do
      assert {:error, error} = ManualWerewolfCountValid.validate(changeset(:manual, 0), [], %{})
      assert Keyword.fetch!(error, :field) == :manual_werewolf_count
    end

    test "a nil or low count is accepted in automatic mode, since it is not read there" do
      assert ManualWerewolfCountValid.validate(changeset(:automatic, nil), [], %{}) == :ok
      assert ManualWerewolfCountValid.validate(changeset(:automatic, 0), [], %{}) == :ok
    end
  end
end
