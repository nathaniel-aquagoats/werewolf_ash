defmodule WerewolfAsh.Games.ActionTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias Ash.Seed
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Action

  @start ~U[2026-06-15 09:30:00Z]
  @dusk ~U[2026-06-15 20:00:00Z]
  @dawn ~U[2026-06-16 08:00:00Z]

  # Seats an owner + 4 more players (5 total, Etc/UTC, 08:00/20:00 windows),
  # starts the game so it lands in a day phase, and returns the game plus
  # every player keyed by their dealt role.
  defp started_game do
    owner = generate(user())
    game = generate(game(owner_id: owner.id))
    generate_many(player(game_id: game.id), 4)
    game = Games.start_game!(game, %{now: @start}, actor: owner)

    players =
      Games.list_players!(query: [filter: [game_id: game.id]])
      |> Map.new(&{&1.role, &1})

    assert map_size(players) == 5

    %{game: game, players: players}
  end

  defp current_phase(game) do
    Games.get_game!(game.id, load: :current_phase).current_phase
  end

  defp force_state(game, state) do
    game
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:state, state)
    |> Ash.update!()
  end

  describe "create_action/4,5" do
    setup do
      started_game()
    end

    test "a living player's day vote succeeds and is readable back", %{game: game, players: p} do
      day = current_phase(game)

      action = Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote)

      assert action.type == :vote
      assert Games.get_action!(action.id).id == action.id

      assert Games.list_actions!(query: [filter: [phase_id: day.id]])
             |> Enum.any?(&(&1.id == action.id))
    end

    test "the seer's night investigation succeeds with a computed result", %{
      game: game,
      players: p
    } do
      game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(game)

      action = Games.create_action!(night.id, p.seer.id, p.werewolf.id, :investigate)

      assert action.result == %{"is_werewolf" => true}
    end

    test "the bodyguard's day protection succeeds", %{game: game, players: p} do
      day = current_phase(game)

      action = Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect)

      assert action.type == :protect
    end

    test "the pending hunter, already dead, can shoot", %{game: game, players: p} do
      Games.update_player!(p.hunter, %{alive: false})
      game = force_state(game, :hunter_pending)
      day = current_phase(game)

      action = Games.create_action!(day.id, p.hunter.id, p.villager.id, :shoot)

      assert action.type == :shoot
    end

    test "rejects a dead actor's vote, investigation or protection (rule 1)", %{
      game: game,
      players: p
    } do
      day = current_phase(game)
      night_game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(night_game)

      Games.update_player!(p.villager, %{alive: false})
      Games.update_player!(p.seer, %{alive: false})
      Games.update_player!(p.bodyguard, %{alive: false})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.create_action(day.id, p.villager.id, p.werewolf.id, :vote)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.create_action(night.id, p.seer.id, p.werewolf.id, :investigate)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.create_action(day.id, p.bodyguard.id, p.villager.id, :protect)

      assert Games.list_actions!(query: [filter: [phase_id: day.id]]) == []
      assert Games.list_actions!(query: [filter: [phase_id: night.id]]) == []
    end

    test "rejects a :vote outside a day phase (rule 2)", %{game: game, players: p} do
      game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(game)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_action(night.id, p.villager.id, p.werewolf.id, :vote)

      assert Games.list_actions!(query: [filter: [phase_id: night.id]]) == []
    end

    test "rejects :investigate outside a night phase, or by a non-seer (rule 4)", %{
      game: game,
      players: p
    } do
      day = current_phase(game)
      night = current_phase(Games.end_day!(game, %{now: @dusk}))

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_action(day.id, p.seer.id, p.werewolf.id, :investigate)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_action(night.id, p.villager.id, p.werewolf.id, :investigate)
    end

    test "rejects :protect outside a day phase, or by a non-bodyguard (rule 5)", %{
      game: game,
      players: p
    } do
      day = current_phase(game)
      night = current_phase(Games.end_day!(game, %{now: @dusk}))

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_action(night.id, p.bodyguard.id, p.villager.id, :protect)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_action(day.id, p.villager.id, p.werewolf.id, :protect)
    end

    test "rejects a bodyguard protecting themselves (rule 6)", %{game: game, players: p} do
      day = current_phase(game)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :target_id}]}} =
               Games.create_action(day.id, p.bodyguard.id, p.bodyguard.id, :protect)
    end

    test "rejects a shot from anyone but the pending hunter (rule 7)", %{game: game, players: p} do
      game = force_state(game, :hunter_pending)
      day = current_phase(game)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.create_action(day.id, p.villager.id, p.werewolf.id, :shoot)
    end

    test "refuses a second action of the same type in the same phase (rule 9)", %{
      game: game,
      players: p
    } do
      day = current_phase(game)
      first = Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :phase_id}]}} =
               Games.create_action(day.id, p.villager.id, p.bodyguard.id, :vote)

      unchanged = Games.get_action!(first.id)
      assert unchanged.target_id == first.target_id
      assert unchanged.result == first.result
    end

    test "a different type in the same phase, or the same type in a later phase, still succeeds",
         %{game: game, players: p} do
      day = current_phase(game)
      Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote)

      assert %{type: :protect} =
               Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect)

      game = Games.end_day!(game, %{now: @dusk})
      game = Games.end_night!(game, %{now: @dawn})
      day2 = current_phase(game)

      assert %{type: :vote} = Games.create_action!(day2.id, p.villager.id, p.werewolf.id, :vote)
    end

    test "rejects type: :kill outright (rule 12)", %{game: game, players: p} do
      day = current_phase(game)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_action(day.id, p.werewolf.id, p.villager.id, :kill)
    end
  end

  describe "create_kill_action/3,4" do
    setup do
      %{game: game, players: p} = started_game()
      day = current_phase(game)
      game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(game)
      %{game: game, players: p, day: day, night: night}
    end

    test "a living werewolf's kill lands immediately", %{players: p, night: night} do
      action = Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id)

      assert action.type == :kill
      assert action.result == %{"killed" => true}
      assert Games.get_player!(p.villager.id).alive == false
    end

    test "rejects a dead actor, a non-werewolf actor, and a day-phase attempt (rules 1, 3)", %{
      players: p,
      day: day,
      night: night
    } do
      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_kill_action(night.id, p.villager.id, p.bodyguard.id)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_kill_action(day.id, p.werewolf.id, p.villager.id)

      Games.update_player!(p.werewolf, %{alive: false})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.create_kill_action(night.id, p.werewolf.id, p.villager.id)

      assert Games.list_actions!(query: [filter: [phase_id: night.id]]) == []
    end

    test "a protected target survives; the kill is spent", %{
      players: p,
      day: day,
      night: night
    } do
      Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect)

      action = Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id)

      assert action.result == %{"killed" => false}
      assert Games.get_player!(p.villager.id).alive == true
    end

    test "a second kill for the same phase always fails (rule 11)", %{
      game: game,
      players: p,
      night: night
    } do
      first = Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id)
      other_wolf = generate(player(game_id: game.id, role: :werewolf))

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :phase_id}]}} =
               Games.create_kill_action(night.id, other_wolf.id, p.bodyguard.id)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :phase_id}]}} =
               Games.create_kill_action(night.id, p.werewolf.id, p.bodyguard.id)

      unchanged = Games.get_action!(first.id)
      assert unchanged.target_id == first.target_id
      assert unchanged.result == first.result
      assert Games.get_player!(p.villager.id).alive == false
      assert Games.get_player!(p.bodyguard.id).alive == true
    end

    test "the database refuses a second kill row even bypassing the application", %{
      game: game,
      players: p,
      night: night
    } do
      Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id)
      other_wolf = generate(player(game_id: game.id, role: :werewolf))

      assert_raise Ash.Error.Invalid, fn ->
        Seed.seed!(Action, %{
          phase_id: night.id,
          actor_id: other_wolf.id,
          target_id: p.bodyguard.id,
          type: :kill
        })
      end
    end
  end

  describe "end to end" do
    test "day/night path: bodyguard protects, a vote lands, a kill lands, the seer investigates" do
      %{game: game, players: p} = started_game()
      day = current_phase(game)

      Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect)
      Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote)

      game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(game)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_action(night.id, p.villager.id, p.werewolf.id, :vote)

      target = p.hunter
      kill = Games.create_kill_action!(night.id, p.werewolf.id, target.id)

      assert kill.result == %{"killed" => true}
      assert Games.get_player!(target.id).alive == false

      seer_action = Games.create_action!(night.id, p.seer.id, p.werewolf.id, :investigate)
      assert seer_action.result == %{"is_werewolf" => true}

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_kill_action(night.id, p.villager.id, p.bodyguard.id)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :phase_id}]}} =
               Games.create_kill_action(night.id, p.werewolf.id, p.bodyguard.id)

      assert Games.get_player!(target.id).alive == false

      assert Games.list_actions!(query: [filter: [phase_id: night.id, type: :kill]])
             |> length() == 1
    end

    test "protected-kill path: a protected target survives the werewolf's kill" do
      %{game: game, players: p} = started_game()
      day = current_phase(game)

      Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect)

      game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(game)

      kill = Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id)

      assert kill.result == %{"killed" => false}
      assert Games.get_player!(p.villager.id).alive == true
    end

    test "hunter path: only the dead, pending hunter may shoot" do
      %{game: game, players: p} = started_game()

      Games.update_player!(p.hunter, %{alive: false})
      game = force_state(game, :hunter_pending)
      day = current_phase(game)

      shot = Games.create_action!(day.id, p.hunter.id, p.villager.id, :shoot)
      assert shot.type == :shoot

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.create_action(day.id, p.villager.id, p.werewolf.id, :shoot)
    end
  end
end
