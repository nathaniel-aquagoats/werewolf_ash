defmodule WerewolfAsh.Games.Game.RoleAssignmentTest do
  use ExUnit.Case, async: true

  alias WerewolfAsh.Games.Game.RoleAssignment

  @default_settings %{
    role_distribution_mode: :automatic,
    manual_werewolf_count: nil,
    seer_enabled: true,
    bodyguard_enabled: true,
    hunter_enabled: true
  }

  describe "composition/2" do
    test "the minimum of 5 players deals one of each special role and one wolf" do
      assert RoleAssignment.composition(5, @default_settings) |> Enum.frequencies() ==
               %{seer: 1, bodyguard: 1, hunter: 1, werewolf: 1, villager: 1}
    end

    test "the wolf count only grows past the boundary at 8" do
      assert RoleAssignment.composition(7, @default_settings) |> Enum.frequencies() ==
               %{seer: 1, bodyguard: 1, hunter: 1, werewolf: 1, villager: 3}

      assert RoleAssignment.composition(8, @default_settings) |> Enum.frequencies() ==
               %{seer: 1, bodyguard: 1, hunter: 1, werewolf: 2, villager: 3}
    end

    test "every seat gets exactly one role, none left nil" do
      composition = RoleAssignment.composition(11, @default_settings)

      assert length(composition) == 11
      refute Enum.any?(composition, &is_nil/1)
    end

    test "manual mode uses the configured count verbatim, regardless of player_count" do
      settings = %{@default_settings | role_distribution_mode: :manual, manual_werewolf_count: 3}

      assert RoleAssignment.composition(10, settings) |> Enum.frequencies() ==
               %{seer: 1, bodyguard: 1, hunter: 1, werewolf: 3, villager: 4}
    end

    test "each special can be disabled independently" do
      assert RoleAssignment.composition(5, %{@default_settings | seer_enabled: false})
             |> Enum.frequencies() ==
               %{bodyguard: 1, hunter: 1, werewolf: 1, villager: 2}

      assert RoleAssignment.composition(5, %{@default_settings | bodyguard_enabled: false})
             |> Enum.frequencies() ==
               %{seer: 1, hunter: 1, werewolf: 1, villager: 2}

      assert RoleAssignment.composition(5, %{@default_settings | hunter_enabled: false})
             |> Enum.frequencies() ==
               %{seer: 1, bodyguard: 1, werewolf: 1, villager: 2}
    end

    test "all three specials can be disabled at once" do
      settings = %{
        @default_settings
        | seer_enabled: false,
          bodyguard_enabled: false,
          hunter_enabled: false
      }

      assert RoleAssignment.composition(5, settings) |> Enum.frequencies() ==
               %{werewolf: 1, villager: 4}
    end

    test "handles a seat count below 5 now that the old guard is gone" do
      assert RoleAssignment.composition(4, @default_settings) |> Enum.frequencies() ==
               %{seer: 1, bodyguard: 1, hunter: 1, werewolf: 1}
    end

    test "the max(1, ...) floor still applies below 4, where div alone would give zero wolves" do
      settings = %{
        @default_settings
        | seer_enabled: false,
          bodyguard_enabled: false,
          hunter_enabled: false
      }

      assert RoleAssignment.composition(2, settings) |> Enum.frequencies() ==
               %{werewolf: 1, villager: 1}
    end
  end
end
