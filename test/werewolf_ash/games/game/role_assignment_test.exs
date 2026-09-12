defmodule WerewolfAsh.Games.Game.RoleAssignmentTest do
  use ExUnit.Case, async: true

  alias WerewolfAsh.Games.Game.RoleAssignment

  describe "composition/1" do
    test "the minimum of 5 players deals one of each special role and one wolf" do
      assert RoleAssignment.composition(5) |> Enum.frequencies() ==
               %{seer: 1, bodyguard: 1, hunter: 1, werewolf: 1, villager: 1}
    end

    test "the wolf count only grows past the boundary at 8" do
      assert RoleAssignment.composition(7) |> Enum.frequencies() ==
               %{seer: 1, bodyguard: 1, hunter: 1, werewolf: 1, villager: 3}

      assert RoleAssignment.composition(8) |> Enum.frequencies() ==
               %{seer: 1, bodyguard: 1, hunter: 1, werewolf: 2, villager: 3}
    end

    test "every seat gets exactly one role, none left nil" do
      composition = RoleAssignment.composition(11)

      assert length(composition) == 11
      refute Enum.any?(composition, &is_nil/1)
    end
  end
end
