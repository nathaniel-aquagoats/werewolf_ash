defmodule WerewolfAsh.Games.Reactors.ResolveLynchTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Reactors.ResolveLynch

  defp resolve(phase, game),
    do: Reactor.run(ResolveLynch, %{phase_id: phase.id, game_id: game.id}, %{}, async?: false)

  defp force_state(game, state) do
    game
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:state, state)
    |> Ash.update!()
  end

  defp vote!(day, actor, target),
    do: Games.create_action!(day.id, actor.id, target.id, :vote, authorize?: false)

  describe "tally/1" do
    test "groups votes by target into voter id lists" do
      votes = [
        %Action{type: :vote, actor_id: "a1", target_id: "t1"},
        %Action{type: :vote, actor_id: "a2", target_id: "t1"},
        %Action{type: :vote, actor_id: "a3", target_id: "t2"}
      ]

      tally = ResolveLynch.tally(votes)

      assert Enum.sort(tally["t1"]) == ["a1", "a2"]
      assert tally["t2"] == ["a3"]
    end

    test "a target nobody voted for is absent, not a zero" do
      votes = [%Action{type: :vote, actor_id: "a1", target_id: "t1"}]

      refute Map.has_key?(ResolveLynch.tally(votes), "t2")
    end

    test "an empty list returns an empty map" do
      assert ResolveLynch.tally([]) == %{}
    end

    test "ignores any action that is not a :vote" do
      votes = [
        %Action{type: :vote, actor_id: "a1", target_id: "t1"},
        %Action{type: :protect, actor_id: "a2", target_id: "t1"}
      ]

      assert ResolveLynch.tally(votes) == %{"t1" => ["a1"]}
    end
  end

  describe "decide/1" do
    test "a single plurality winner is lynched" do
      assert ResolveLynch.decide(%{"t1" => ["a1", "a2"], "t2" => ["a3"]}) == {:lynch, "t1"}
    end

    test "a two-way tie at the top decides no_lynch" do
      assert ResolveLynch.decide(%{"t1" => ["a1"], "t2" => ["a2"]}) == :no_lynch
    end

    test "an empty tally decides no_lynch" do
      assert ResolveLynch.decide(%{}) == :no_lynch
    end

    test "a tie among the lower counts still lynches the single leader" do
      tally = %{"t1" => ["a1", "a2"], "t2" => ["a3"], "t3" => ["a4"]}

      assert ResolveLynch.decide(tally) == {:lynch, "t1"}
    end
  end

  describe "run/1 against a real game" do
    setup do
      %{game: generate(game())}
    end

    test "a plurality lynch kills the target and leaves the game running (rules 6, 12, 15)", %{
      game: game
    } do
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      wolf = generate(player(game_id: game.id, role: :werewolf))
      target = generate(player(game_id: game.id, role: :villager))
      other = generate(player(game_id: game.id, role: :villager))

      vote!(day, other, target)
      vote!(day, wolf, target)

      assert {:ok, %{outcome: :continue}} = resolve(day, game)
      assert Games.get_player!(target.id, authorize?: false).alive == false
      assert Games.get_player!(wolf.id, authorize?: false).alive == true
      assert Games.get_player!(other.id, authorize?: false).alive == true
    end

    test "a plurality lynch that removes the last living wolf finishes the game as :village (rules 6, 12, 13)",
         %{game: game} do
      game = force_state(game, :day)
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      wolf = generate(player(game_id: game.id, role: :werewolf))
      villager1 = generate(player(game_id: game.id, role: :villager))
      villager2 = generate(player(game_id: game.id, role: :villager))

      vote!(day, villager1, wolf)
      vote!(day, villager2, wolf)

      assert {:ok, %{outcome: :village_wins, game: finished}} = resolve(day, game)
      assert finished.state == :finished
      assert finished.winner == :village
      assert Games.get_player!(wolf.id, authorize?: false).alive == false
    end

    test "a tied vote kills nobody and still runs the win check (rules 3, 7, 12)", %{game: game} do
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      wolf = generate(player(game_id: game.id, role: :werewolf))
      villager1 = generate(player(game_id: game.id, role: :villager))
      villager2 = generate(player(game_id: game.id, role: :villager))

      vote!(day, villager1, wolf)
      vote!(day, wolf, villager1)

      assert {:ok, %{outcome: :continue}} = resolve(day, game)
      assert Games.get_player!(wolf.id, authorize?: false).alive == true
      assert Games.get_player!(villager1.id, authorize?: false).alive == true
      assert Games.get_player!(villager2.id, authorize?: false).alive == true
    end

    test "an existing :protect action for the lynched player does not save them (rule 10)", %{
      game: game
    } do
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      generate(player(game_id: game.id, role: :werewolf))
      bodyguard = generate(player(game_id: game.id, role: :bodyguard))
      target = generate(player(game_id: game.id, role: :villager))
      voter1 = generate(player(game_id: game.id, role: :villager))
      voter2 = generate(player(game_id: game.id, role: :villager))

      Games.create_action!(day.id, bodyguard.id, target.id, :protect, authorize?: false)
      vote!(day, voter1, target)
      vote!(day, voter2, target)

      assert {:ok, _} = resolve(day, game)
      assert Games.get_player!(target.id, authorize?: false).alive == false
    end

    test "votes cast in a different phase of the same game are not counted (rule 5)", %{
      game: game
    } do
      other_day = generate(phase(game_id: game.id, kind: :day, number: 1))
      resolved_day = generate(phase(game_id: game.id, kind: :day, number: 2))

      generate(player(game_id: game.id, role: :werewolf))
      voter1 = generate(player(game_id: game.id, role: :villager))
      voter2 = generate(player(game_id: game.id, role: :villager))
      elsewhere_target = generate(player(game_id: game.id, role: :villager))
      resolved_target = generate(player(game_id: game.id, role: :villager))

      vote!(other_day, voter1, elsewhere_target)
      vote!(resolved_day, voter2, resolved_target)

      assert {:ok, _} = resolve(resolved_day, game)
      assert Games.get_player!(resolved_target.id, authorize?: false).alive == false
      assert Games.get_player!(elsewhere_target.id, authorize?: false).alive == true
    end

    test "a since-dead voter's vote is dropped and can flip the outcome (rule 8)", %{game: game} do
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      generate(player(game_id: game.id, role: :werewolf))
      target_a = generate(player(game_id: game.id, role: :villager))
      target_b = generate(player(game_id: game.id, role: :villager))
      voter_a1 = generate(player(game_id: game.id, role: :villager))
      voter_a2 = generate(player(game_id: game.id, role: :villager))
      voter_b = generate(player(game_id: game.id, role: :villager))

      vote!(day, voter_a1, target_a)
      vote!(day, voter_a2, target_a)
      vote!(day, voter_b, target_b)

      Games.update_player!(voter_a1, %{alive: false})

      assert {:ok, _} = resolve(day, game)
      assert Games.get_player!(target_a.id, authorize?: false).alive == true
      assert Games.get_player!(target_b.id, authorize?: false).alive == true
    end

    test "a since-dead target's vote is dropped entirely, not counted as a no-op (rule 9)", %{
      game: game
    } do
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      generate(player(game_id: game.id, role: :werewolf))
      target_c = generate(player(game_id: game.id, role: :villager))
      target_d = generate(player(game_id: game.id, role: :villager))
      voter1 = generate(player(game_id: game.id, role: :villager))
      voter2 = generate(player(game_id: game.id, role: :villager))
      voter3 = generate(player(game_id: game.id, role: :villager))

      vote!(day, voter1, target_c)
      vote!(day, voter2, target_c)
      vote!(day, voter3, target_d)

      Games.update_player!(target_c, %{alive: false})

      assert {:ok, _} = resolve(day, game)
      assert Games.get_player!(target_d.id, authorize?: false).alive == false
      assert Games.get_player!(target_c.id, authorize?: false).alive == false
    end
  end
end
