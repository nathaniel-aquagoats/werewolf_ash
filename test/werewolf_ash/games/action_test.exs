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
      Games.list_players!(query: [filter: [game_id: game.id]], authorize?: false)
      |> Map.new(&{&1.role, &1})

    assert map_size(players) == 5

    %{game: game, players: players}
  end

  defp current_phase(game) do
    Games.get_game!(game.id, load: :current_phase, authorize?: false).current_phase
  end

  # rule 7 - every Action create/kill call in this file submits as the
  # acting player's own seat; `%{id: player.user_id}` is enough of an actor
  # to satisfy the policy (the same shape games_test.exs's own
  # `update_settings!/2` helper already uses for `ActorIsOwner`), without a
  # real `User` fetch.
  defp actor_for(player), do: %{id: player.user_id}

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

      action =
        Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote,
          actor: actor_for(p.villager)
        )

      assert action.type == :vote
      assert Games.get_action!(action.id, authorize?: false).id == action.id

      assert Games.list_actions!(query: [filter: [phase_id: day.id]], authorize?: false)
             |> Enum.any?(&(&1.id == action.id))
    end

    test "the seer's night investigation succeeds with a computed result", %{
      game: game,
      players: p
    } do
      game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(game)

      action =
        Games.create_action!(night.id, p.seer.id, p.werewolf.id, :investigate,
          actor: actor_for(p.seer)
        )

      assert action.result == %{"is_werewolf" => true}
    end

    test "the bodyguard's day protection succeeds", %{game: game, players: p} do
      day = current_phase(game)

      action =
        Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect,
          actor: actor_for(p.bodyguard)
        )

      assert action.type == :protect
    end

    test "the pending hunter, already dead, can shoot", %{game: game, players: p} do
      Games.update_player!(p.hunter, %{alive: false})
      game = force_state(game, :hunter_pending)
      day = current_phase(game)

      action =
        Games.create_action!(day.id, p.hunter.id, p.villager.id, :shoot,
          actor: actor_for(p.hunter)
        )

      assert action.type == :shoot
    end

    test "rejects a dead actor's vote, investigation or protection (rule 1)", %{
      game: game,
      players: p
    } do
      day = current_phase(game)

      # Only the villager and bodyguard die before `end_day!` runs: 1 wolf
      # against the 2 non-wolves (seer, hunter) still alive is not wolf
      # parity, so the win check `end_day!` composes leaves the game in
      # :continue and a night phase opens, regardless of whether
      # werewolf_ash-qss.5 has merged. The seer dies only afterward, once
      # the night phase it's tested against already exists.
      Games.update_player!(p.villager, %{alive: false})
      Games.update_player!(p.bodyguard, %{alive: false})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.create_action(day.id, p.villager.id, p.werewolf.id, :vote,
                 actor: actor_for(p.villager)
               )

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.create_action(day.id, p.bodyguard.id, p.werewolf.id, :protect,
                 actor: actor_for(p.bodyguard)
               )

      night_game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(night_game)

      Games.update_player!(p.seer, %{alive: false})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.create_action(night.id, p.seer.id, p.werewolf.id, :investigate,
                 actor: actor_for(p.seer)
               )

      assert Games.list_actions!(query: [filter: [phase_id: day.id]], authorize?: false) == []
      assert Games.list_actions!(query: [filter: [phase_id: night.id]], authorize?: false) == []
    end

    test "rejects a dead target for a vote, investigation or protection (werewolf_ash-qss.18 rule 1)",
         %{game: game, players: p} do
      day = current_phase(game)

      Games.update_player!(p.hunter, %{alive: false})

      # Both day-phase assertions run while `day` is still open: once
      # werewolf_ash-qss.21's phase-not-ended check exists, a :vote/:protect
      # issued after `end_day!` against this same, now-closed `day` would
      # also fail that check, turning each single-error assertion below
      # into a two-element list.
      assert {:error, %Ash.Error.Invalid{errors: [%{field: :target_id}]}} =
               Games.create_action(day.id, p.villager.id, p.hunter.id, :vote,
                 actor: actor_for(p.villager)
               )

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :target_id}]}} =
               Games.create_action(day.id, p.bodyguard.id, p.hunter.id, :protect,
                 actor: actor_for(p.bodyguard)
               )

      night_game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(night_game)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :target_id}]}} =
               Games.create_action(night.id, p.seer.id, p.hunter.id, :investigate,
                 actor: actor_for(p.seer)
               )

      assert Games.list_actions!(query: [filter: [phase_id: day.id]], authorize?: false) == []
      assert Games.list_actions!(query: [filter: [phase_id: night.id]], authorize?: false) == []
    end

    test "rejects a cross-game actor or target (werewolf_ash-qss.18 rules 2, 3)", %{
      game: game,
      players: p
    } do
      day = current_phase(game)
      other_game = generate(game())
      outsider = generate(player(game_id: other_game.id))

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.create_action(day.id, outsider.id, p.werewolf.id, :vote,
                 actor: actor_for(outsider)
               )

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :target_id}]}} =
               Games.create_action(day.id, p.villager.id, outsider.id, :vote,
                 actor: actor_for(p.villager)
               )

      assert Games.list_actions!(query: [filter: [phase_id: day.id]], authorize?: false) == []
    end

    test "rejects consecutive-day protection of the same player, but allows a different target (werewolf_ash-qss.18 rule 4)",
         %{game: game, players: p} do
      day1 = current_phase(game)

      Games.create_action!(day1.id, p.bodyguard.id, p.villager.id, :protect,
        actor: actor_for(p.bodyguard)
      )

      game = Games.end_day!(game, %{now: @dusk})
      game = Games.end_night!(game, %{now: @dawn})
      day2 = current_phase(game)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :target_id}]}} =
               Games.create_action(day2.id, p.bodyguard.id, p.villager.id, :protect,
                 actor: actor_for(p.bodyguard)
               )

      assert %{type: :protect} =
               Games.create_action!(day2.id, p.bodyguard.id, p.seer.id, :protect,
                 actor: actor_for(p.bodyguard)
               )
    end

    test "rejects a :vote outside a day phase (rule 2)", %{game: game, players: p} do
      game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(game)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_action(night.id, p.villager.id, p.werewolf.id, :vote,
                 actor: actor_for(p.villager)
               )

      assert Games.list_actions!(query: [filter: [phase_id: night.id]], authorize?: false) == []
    end

    test "rejects :investigate outside a night phase, or by a non-seer (rule 4)", %{
      game: game,
      players: p
    } do
      day = current_phase(game)
      night = current_phase(Games.end_day!(game, %{now: @dusk}))

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_action(day.id, p.seer.id, p.werewolf.id, :investigate,
                 actor: actor_for(p.seer)
               )

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_action(night.id, p.villager.id, p.werewolf.id, :investigate,
                 actor: actor_for(p.villager)
               )
    end

    test "rejects :protect outside a day phase, or by a non-bodyguard (rule 5)", %{
      game: game,
      players: p
    } do
      day = current_phase(game)

      # Runs against the still-open `day` first: once werewolf_ash-qss.21's
      # own phase-not-ended check exists, a :protect issued after
      # `end_day!` against that same, now-closed `day` would also fail that
      # check, turning this single-error assertion into a two-element list.
      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_action(day.id, p.villager.id, p.werewolf.id, :protect,
                 actor: actor_for(p.villager)
               )

      night = current_phase(Games.end_day!(game, %{now: @dusk}))

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_action(night.id, p.bodyguard.id, p.villager.id, :protect,
                 actor: actor_for(p.bodyguard)
               )
    end

    test "rejects a bodyguard protecting themselves (rule 6)", %{game: game, players: p} do
      day = current_phase(game)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :target_id}]}} =
               Games.create_action(day.id, p.bodyguard.id, p.bodyguard.id, :protect,
                 actor: actor_for(p.bodyguard)
               )
    end

    test "rejects a shot from anyone but the pending hunter (rule 7)", %{game: game, players: p} do
      game = force_state(game, :hunter_pending)
      day = current_phase(game)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.create_action(day.id, p.villager.id, p.werewolf.id, :shoot,
                 actor: actor_for(p.villager)
               )
    end

    test "a second :vote in the same phase recasts the same row, rather than being refused (rule 1)",
         %{game: game, players: p} do
      day = current_phase(game)

      first =
        Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote,
          actor: actor_for(p.villager)
        )

      second =
        Games.create_action!(day.id, p.villager.id, p.bodyguard.id, :vote,
          actor: actor_for(p.villager)
        )

      assert second.id == first.id
      assert Games.get_action!(first.id, authorize?: false).target_id == p.bodyguard.id

      assert Games.list_actions!(
               query: [filter: [phase_id: day.id, actor_id: p.villager.id, type: :vote]],
               authorize?: false
             )
             |> length() == 1
    end

    test "a second :protect in the same phase recasts the same row, rather than being refused (rule 2)",
         %{game: game, players: p} do
      day = current_phase(game)

      first =
        Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect,
          actor: actor_for(p.bodyguard)
        )

      second =
        Games.create_action!(day.id, p.bodyguard.id, p.seer.id, :protect,
          actor: actor_for(p.bodyguard)
        )

      assert second.id == first.id
      assert Games.get_action!(first.id, authorize?: false).target_id == p.seer.id

      assert Games.list_actions!(
               query: [filter: [phase_id: day.id, actor_id: p.bodyguard.id, type: :protect]],
               authorize?: false
             )
             |> length() == 1
    end

    test "a recast targeting a dead player is rejected the same way a first vote would be (rule 3)",
         %{game: game, players: p} do
      day = current_phase(game)

      Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote,
        actor: actor_for(p.villager)
      )

      Games.update_player!(p.hunter, %{alive: false})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :target_id}]}} =
               Games.create_action(day.id, p.villager.id, p.hunter.id, :vote,
                 actor: actor_for(p.villager)
               )
    end

    test "a recast by a now-dead actor is rejected on :actor_id (rule 3)", %{
      game: game,
      players: p
    } do
      day = current_phase(game)

      Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote,
        actor: actor_for(p.villager)
      )

      Games.update_player!(p.villager, %{alive: false})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.create_action(day.id, p.villager.id, p.bodyguard.id, :vote,
                 actor: actor_for(p.villager)
               )
    end

    test "a :vote or :protect against an already-ended day phase is rejected on :phase_id, first or recast (rule 4)",
         %{game: game, players: p} do
      day = current_phase(game)

      Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote,
        actor: actor_for(p.villager)
      )

      Games.end_day!(game, %{now: @dusk})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :phase_id}]}} =
               Games.create_action(day.id, p.villager.id, p.bodyguard.id, :vote,
                 actor: actor_for(p.villager)
               )

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :phase_id}]}} =
               Games.create_action(day.id, p.bodyguard.id, p.villager.id, :protect,
                 actor: actor_for(p.bodyguard)
               )
    end

    test "refuses a second :investigate in the same phase, a type recast leaves untouched (rule 5)",
         %{game: game, players: p} do
      night = current_phase(Games.end_day!(game, %{now: @dusk}))

      first =
        Games.create_action!(night.id, p.seer.id, p.werewolf.id, :investigate,
          actor: actor_for(p.seer)
        )

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :phase_id}]}} =
               Games.create_action(night.id, p.seer.id, p.villager.id, :investigate,
                 actor: actor_for(p.seer)
               )

      unchanged = Games.get_action!(first.id, authorize?: false)
      assert unchanged.target_id == first.target_id
    end

    test "a different type in the same phase, or the same type in a later phase, still succeeds",
         %{game: game, players: p} do
      day = current_phase(game)

      Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote,
        actor: actor_for(p.villager)
      )

      # A second, opposing vote (werewolf_ash-qss.5 rules 2, 3) ties the day
      # so this test's own single werewolf survives `end_day!` below; the
      # rule's own behaviour is covered in resolve_lynch_test.exs.
      Games.create_action!(day.id, p.werewolf.id, p.villager.id, :vote,
        actor: actor_for(p.werewolf)
      )

      assert %{type: :protect} =
               Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect,
                 actor: actor_for(p.bodyguard)
               )

      game = Games.end_day!(game, %{now: @dusk})
      game = Games.end_night!(game, %{now: @dawn})
      day2 = current_phase(game)

      assert %{type: :vote} =
               Games.create_action!(day2.id, p.villager.id, p.werewolf.id, :vote,
                 actor: actor_for(p.villager)
               )
    end

    test "rejects type: :kill outright (rule 12)", %{game: game, players: p} do
      day = current_phase(game)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_action(day.id, p.werewolf.id, p.villager.id, :kill,
                 actor: actor_for(p.werewolf)
               )
    end
  end

  describe "withdraw_action/3" do
    setup do
      started_game()
    end

    test "a living actor withdrawing an existing :vote deletes it", %{game: game, players: p} do
      day = current_phase(game)

      Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote,
        actor: actor_for(p.villager)
      )

      Games.withdraw_action!(day.id, p.villager.id, :vote, actor: actor_for(p.villager))

      assert Games.list_actions!(
               query: [filter: [phase_id: day.id, actor_id: p.villager.id, type: :vote]],
               authorize?: false
             ) == []
    end

    test "a living bodyguard withdrawing an existing :protect deletes it", %{
      game: game,
      players: p
    } do
      day = current_phase(game)

      Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect,
        actor: actor_for(p.bodyguard)
      )

      Games.withdraw_action!(day.id, p.bodyguard.id, :protect, actor: actor_for(p.bodyguard))

      assert Games.list_actions!(
               query: [filter: [phase_id: day.id, actor_id: p.bodyguard.id, type: :protect]],
               authorize?: false
             ) == []
    end

    test "rejects any type other than :vote or :protect, on :type", %{game: game, players: p} do
      night = current_phase(Games.end_day!(game, %{now: @dusk}))

      Games.create_action!(night.id, p.seer.id, p.werewolf.id, :investigate,
        actor: actor_for(p.seer)
      )

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.withdraw_action(night.id, p.seer.id, :investigate, actor: actor_for(p.seer))
    end

    test "rejects a dead actor's withdrawal on :actor_id, even with nothing to withdraw (rules 7, 12)",
         %{game: game, players: p} do
      day = current_phase(game)
      Games.update_player!(p.villager, %{alive: false})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.withdraw_action(day.id, p.villager.id, :vote, actor: actor_for(p.villager))
    end

    test "rejects withdrawal against an already-ended phase on :phase_id, even with nothing to withdraw (rules 8, 12)",
         %{game: game, players: p} do
      day = current_phase(game)
      Games.end_day!(game, %{now: @dusk})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :phase_id}]}} =
               Games.withdraw_action(day.id, p.bodyguard.id, :protect,
                 actor: actor_for(p.bodyguard)
               )
    end

    test "withdrawing something never made quietly succeeds and changes nothing (rule 9)", %{
      game: game,
      players: p
    } do
      day = current_phase(game)

      list_day_actions = fn ->
        Games.list_actions!(query: [filter: [phase_id: day.id]], authorize?: false)
      end

      before_count = length(list_day_actions.())

      Games.withdraw_action!(day.id, p.villager.id, :vote, actor: actor_for(p.villager))

      assert length(list_day_actions.()) == before_count
    end

    test "forbids withdrawing on behalf of a different user's seat (rule 11)", %{
      game: game,
      players: p
    } do
      day = current_phase(game)

      Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote,
        actor: actor_for(p.villager)
      )

      other_user = generate(user())

      assert {:error, %Ash.Error.Forbidden{}} =
               Games.withdraw_action(day.id, p.villager.id, :vote, actor: %{id: other_user.id})
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
      action =
        Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id,
          actor: actor_for(p.werewolf)
        )

      assert action.type == :kill
      assert action.result == %{"killed" => true}
      assert Games.get_player!(p.villager.id, authorize?: false).alive == false
    end

    test "rejects a dead actor, a non-werewolf actor, and a day-phase attempt (rules 1, 3)", %{
      players: p,
      day: day,
      night: night
    } do
      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_kill_action(night.id, p.villager.id, p.bodyguard.id,
                 actor: actor_for(p.villager)
               )

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_kill_action(day.id, p.werewolf.id, p.villager.id,
                 actor: actor_for(p.werewolf)
               )

      Games.update_player!(p.werewolf, %{alive: false})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.create_kill_action(night.id, p.werewolf.id, p.villager.id,
                 actor: actor_for(p.werewolf)
               )

      assert Games.list_actions!(query: [filter: [phase_id: night.id]], authorize?: false) == []
    end

    test "a protected target survives; the kill is spent" do
      # Own setup, not the describe block's shared `day`/`night`: that
      # block's own `setup` closes `day` with `end_day!` before this test
      # body runs, so a first-ever :protect filed against it here would be
      # rejected on :phase_id (werewolf_ash-qss.21 rule 4) - protection has
      # to be filed while `day` is still open.
      %{game: game, players: p} = started_game()
      day = current_phase(game)

      Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect,
        actor: actor_for(p.bodyguard)
      )

      game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(game)

      action =
        Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id,
          actor: actor_for(p.werewolf)
        )

      assert action.result == %{"killed" => false}
      assert Games.get_player!(p.villager.id, authorize?: false).alive == true
    end

    test "rejects a dead target (werewolf_ash-qss.18 rule 1)", %{players: p, night: night} do
      Games.update_player!(p.villager, %{alive: false})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :target_id}]}} =
               Games.create_kill_action(night.id, p.werewolf.id, p.villager.id,
                 actor: actor_for(p.werewolf)
               )

      assert Games.list_actions!(query: [filter: [phase_id: night.id]], authorize?: false) == []
    end

    test "rejects a cross-game actor and target (werewolf_ash-qss.18 rules 2, 3)", %{
      players: p,
      night: night
    } do
      other_game = generate(game())
      outsider_wolf = generate(player(game_id: other_game.id, role: :werewolf))
      outsider = generate(player(game_id: other_game.id))

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.create_kill_action(night.id, outsider_wolf.id, p.villager.id,
                 actor: actor_for(outsider_wolf)
               )

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :target_id}]}} =
               Games.create_kill_action(night.id, p.werewolf.id, outsider.id,
                 actor: actor_for(p.werewolf)
               )

      assert Games.list_actions!(query: [filter: [phase_id: night.id]], authorize?: false) == []
    end

    test "a dead-target kill is refused without spending the phase's one kill (rule 1 consequence)",
         %{players: p, night: night} do
      Games.update_player!(p.villager, %{alive: false})

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :target_id}]}} =
               Games.create_kill_action(night.id, p.werewolf.id, p.villager.id,
                 actor: actor_for(p.werewolf)
               )

      action =
        Games.create_kill_action!(night.id, p.werewolf.id, p.bodyguard.id,
          actor: actor_for(p.werewolf)
        )

      assert action.result == %{"killed" => true}
      assert Games.get_player!(p.bodyguard.id, authorize?: false).alive == false
    end

    test "a second kill for the same phase always fails (rule 11)", %{
      game: game,
      players: p,
      night: night
    } do
      first =
        Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id,
          actor: actor_for(p.werewolf)
        )

      other_wolf = generate(player(game_id: game.id, role: :werewolf))

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :phase_id}]}} =
               Games.create_kill_action(night.id, other_wolf.id, p.bodyguard.id,
                 actor: actor_for(other_wolf)
               )

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :phase_id}]}} =
               Games.create_kill_action(night.id, p.werewolf.id, p.bodyguard.id,
                 actor: actor_for(p.werewolf)
               )

      unchanged = Games.get_action!(first.id, authorize?: false)
      assert unchanged.target_id == first.target_id
      assert unchanged.result == first.result
      assert Games.get_player!(p.villager.id, authorize?: false).alive == false
      assert Games.get_player!(p.bodyguard.id, authorize?: false).alive == true
    end

    test "the database refuses a second kill row even bypassing the application", %{
      game: game,
      players: p,
      night: night
    } do
      Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id,
        actor: actor_for(p.werewolf)
      )

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

    test "a landed kill that brings wolves to parity finishes the game (werewolf_ash-qss.6 rules 1, 3)",
         %{players: p, night: night} do
      # Bring the non-wolves down to just the target ahead of the kill, the
      # same way resolve_win_test.exs reaches precise counts, so the kill
      # itself is the one that reaches exact wolf parity.
      Games.update_player!(p.bodyguard, %{alive: false})
      Games.update_player!(p.hunter, %{alive: false})

      action =
        Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id,
          actor: actor_for(p.werewolf)
        )

      assert action.result == %{"killed" => true}

      reloaded = Games.get_game!(night.game_id, authorize?: false)
      assert reloaded.state == :finished
      assert reloaded.winner == :wolves
    end

    test "a landed kill that does not reach parity leaves the game in :night with no winner (werewolf_ash-qss.6 rule 4)",
         %{players: p, night: night} do
      action =
        Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id,
          actor: actor_for(p.werewolf)
        )

      assert action.result == %{"killed" => true}

      reloaded = Games.get_game!(night.game_id, authorize?: false)
      assert reloaded.state == :night
      assert is_nil(reloaded.winner)
    end

    test "a landed, non-decisive kill on the dealt hunter is a plain death (werewolf_ash-qss.6 rule 5)",
         %{players: p, night: night} do
      action =
        Games.create_kill_action!(night.id, p.werewolf.id, p.hunter.id,
          actor: actor_for(p.werewolf)
        )

      assert action.result == %{"killed" => true}
      assert Games.get_player!(p.hunter.id, authorize?: false).alive == false

      reloaded = Games.get_game!(night.game_id, authorize?: false)
      assert reloaded.state == :night
    end

    test "a spent (protected) kill runs no win check even at exact wolf parity going in (werewolf_ash-qss.6 rule 2)" do
      # Own setup, not the describe block's shared `day`/`night`: that
      # block's own `setup` closes `day` with `end_day!` before this test
      # body runs, so a first-ever :protect filed against it here would be
      # rejected on :phase_id (werewolf_ash-qss.21 rule 4) - protection has
      # to be filed while `day` is still open.
      %{game: game, players: p} = started_game()
      day = current_phase(game)

      # A second werewolf, so wolf parity can be reached (below) without
      # killing off the bodyguard: werewolf_ash-qss.21 rule 10 means a dead
      # protector's protection no longer counts, and this test needs the
      # protection to still hold when the kill below resolves.
      extra_wolf = generate(player(game_id: game.id, role: :werewolf))

      Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect,
        actor: actor_for(p.bodyguard)
      )

      game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(game)

      # Kill off every other non-wolf directly, so the living counts going
      # into this kill already sit at exact wolf parity (2 wolves, the
      # bodyguard and the protected target as the only non-wolves): a
      # check-runs-regardless-of-spent implementation would finish the game
      # here, a correct one leaves it alone.
      Games.update_player!(p.seer, %{alive: false})
      Games.update_player!(p.hunter, %{alive: false})

      action =
        Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id,
          actor: actor_for(p.werewolf)
        )

      assert action.result == %{"killed" => false}
      assert Games.get_player!(p.villager.id, authorize?: false).alive == true
      assert Games.get_player!(extra_wolf.id, authorize?: false).alive == true

      reloaded = Games.get_game!(night.game_id, authorize?: false)
      assert reloaded.state == :night
      assert is_nil(reloaded.winner)
    end
  end

  describe "end_night (werewolf_ash-qss.6)" do
    setup do
      %{game: game, players: p} = started_game()
      day = current_phase(game)
      game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(game)
      %{game: game, players: p, day: day, night: night}
    end

    test "a night containing a landed, non-decisive kill transitions cleanly to :day, untouched by the transition (rule 6)",
         %{game: game, players: p, night: night} do
      Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id,
        actor: actor_for(p.werewolf)
      )

      actions_before =
        Games.list_actions!(query: [filter: [phase_id: night.id]], authorize?: false)

      kill_count_before = Enum.count(actions_before, &(&1.type == :kill))

      game = Games.end_night!(game, %{now: @dawn})

      actions_after =
        Games.list_actions!(query: [filter: [phase_id: night.id]], authorize?: false)

      kill_count_after = Enum.count(actions_after, &(&1.type == :kill))

      assert game.state == :day
      assert Games.get_player!(p.villager.id, authorize?: false).alive == false
      assert length(actions_after) == length(actions_before)
      assert kill_count_after == kill_count_before

      assert [kill_action] = Enum.filter(actions_after, &(&1.type == :kill))
      assert kill_action.result == %{"killed" => true}
    end

    test "a night whose living counts already decide the game finishes at dawn, leaving no day phase (rules 9, 10)",
         %{game: game, players: p, night: night} do
      Games.update_player!(p.bodyguard, %{alive: false})
      Games.update_player!(p.hunter, %{alive: false})
      Games.update_player!(p.seer, %{alive: false})

      game = Games.end_night!(game, %{now: @dawn})

      assert game.state == :finished
      assert game.winner == :wolves

      assert Games.list_phases!(
               query: [
                 filter: [game_id: game.id, kind: :day, number: night.number + 1]
               ]
             ) == []

      assert Games.list_phases!(query: [filter: [game_id: game.id]])
             |> Enum.all?(&(not is_nil(&1.ended_at)))

      refute is_nil(Games.get_phase!(night.id).ended_at)
    end
  end

  describe "end to end" do
    test "vote path: a villager casts a day vote, recasts it, then withdraws it entirely (werewolf_ash-qss.21 rules 1, 6)" do
      %{game: game, players: p} = started_game()
      day = current_phase(game)

      Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote,
        actor: actor_for(p.villager)
      )

      Games.create_action!(day.id, p.villager.id, p.bodyguard.id, :vote,
        actor: actor_for(p.villager)
      )

      Games.withdraw_action!(day.id, p.villager.id, :vote, actor: actor_for(p.villager))

      assert Games.list_actions!(
               query: [filter: [phase_id: day.id, actor_id: p.villager.id, type: :vote]],
               authorize?: false
             ) == []
    end

    test "protection recast path: a bodyguard recasts from X to Y, so the wolf's kill on X lands (werewolf_ash-qss.21 rule 2)" do
      %{game: game, players: p} = started_game()
      day = current_phase(game)

      Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect,
        actor: actor_for(p.bodyguard)
      )

      Games.create_action!(day.id, p.bodyguard.id, p.seer.id, :protect,
        actor: actor_for(p.bodyguard)
      )

      game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(game)

      kill =
        Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id,
          actor: actor_for(p.werewolf)
        )

      assert kill.result == %{"killed" => true}
      assert Games.get_player!(p.villager.id, authorize?: false).alive == false
    end

    test "a bodyguard who dies before night starts no longer protects their target (werewolf_ash-qss.21 rule 10)" do
      %{game: game, players: p} = started_game()
      day = current_phase(game)

      Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect,
        actor: actor_for(p.bodyguard)
      )

      Games.update_player!(p.bodyguard, %{alive: false})

      game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(game)

      kill =
        Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id,
          actor: actor_for(p.werewolf)
        )

      assert kill.result == %{"killed" => true}
      assert Games.get_player!(p.villager.id, authorize?: false).alive == false
    end

    test "bodyguard path: no consecutive protection, but a gap of one day allows it again (werewolf_ash-qss.18 rule 4)" do
      %{game: game, players: p} = started_game()
      day1 = current_phase(game)

      Games.create_action!(day1.id, p.bodyguard.id, p.villager.id, :protect,
        actor: actor_for(p.bodyguard)
      )

      game = Games.end_day!(game, %{now: @dusk})
      game = Games.end_night!(game, %{now: @dawn})
      day2 = current_phase(game)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :target_id}]}} =
               Games.create_action(day2.id, p.bodyguard.id, p.villager.id, :protect,
                 actor: actor_for(p.bodyguard)
               )

      assert %{type: :protect} =
               Games.create_action!(day2.id, p.bodyguard.id, p.seer.id, :protect,
                 actor: actor_for(p.bodyguard)
               )

      game = Games.end_day!(game, %{now: ~U[2026-06-16 20:00:00Z]})
      game = Games.end_night!(game, %{now: ~U[2026-06-17 08:00:00Z]})
      day3 = current_phase(game)

      assert %{type: :protect} =
               Games.create_action!(day3.id, p.bodyguard.id, p.villager.id, :protect,
                 actor: actor_for(p.bodyguard)
               )
    end

    test "day/night path: bodyguard protects, a vote lands, a kill lands, the seer investigates" do
      %{game: game, players: p} = started_game()
      day = current_phase(game)

      Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect,
        actor: actor_for(p.bodyguard)
      )

      Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote,
        actor: actor_for(p.villager)
      )

      # A second, opposing vote (werewolf_ash-qss.5 rules 2, 3) ties the day
      # so this test's own single werewolf survives `end_day!` below; the
      # rule's own behaviour is covered in resolve_lynch_test.exs.
      Games.create_action!(day.id, p.werewolf.id, p.villager.id, :vote,
        actor: actor_for(p.werewolf)
      )

      game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(game)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_action(night.id, p.villager.id, p.werewolf.id, :vote,
                 actor: actor_for(p.villager)
               )

      target = p.hunter

      kill =
        Games.create_kill_action!(night.id, p.werewolf.id, target.id,
          actor: actor_for(p.werewolf)
        )

      assert kill.result == %{"killed" => true}
      assert Games.get_player!(target.id, authorize?: false).alive == false

      seer_action =
        Games.create_action!(night.id, p.seer.id, p.werewolf.id, :investigate,
          actor: actor_for(p.seer)
        )

      assert seer_action.result == %{"is_werewolf" => true}

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_kill_action(night.id, p.villager.id, p.bodyguard.id,
                 actor: actor_for(p.villager)
               )

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :phase_id}]}} =
               Games.create_kill_action(night.id, p.werewolf.id, p.bodyguard.id,
                 actor: actor_for(p.werewolf)
               )

      assert Games.get_player!(target.id, authorize?: false).alive == false

      assert Games.list_actions!(
               query: [filter: [phase_id: night.id, type: :kill]],
               authorize?: false
             )
             |> length() == 1
    end

    test "protected-kill path: a protected target survives the werewolf's kill" do
      %{game: game, players: p} = started_game()
      day = current_phase(game)

      Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect,
        actor: actor_for(p.bodyguard)
      )

      game = Games.end_day!(game, %{now: @dusk})
      night = current_phase(game)

      kill =
        Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id,
          actor: actor_for(p.werewolf)
        )

      assert kill.result == %{"killed" => false}
      assert Games.get_player!(p.villager.id, authorize?: false).alive == true
    end

    test "two day/night cycles: bodyguard protects, a kill lands, the seer investigates a wolf and then a non-wolf (werewolf_ash-qss.6 rules 1, 4, 6, 8, 11)" do
      %{game: game, players: p} = started_game()
      day1 = current_phase(game)

      protect1 =
        Games.create_action!(day1.id, p.bodyguard.id, p.hunter.id, :protect,
          actor: actor_for(p.bodyguard)
        )

      game = Games.end_day!(game, %{now: @dusk})
      night1 = current_phase(game)

      kill =
        Games.create_kill_action!(night1.id, p.werewolf.id, p.villager.id,
          actor: actor_for(p.werewolf)
        )

      assert kill.result == %{"killed" => true}

      seer_action1 =
        Games.create_action!(night1.id, p.seer.id, p.werewolf.id, :investigate,
          actor: actor_for(p.seer)
        )

      assert seer_action1.result == %{"is_werewolf" => true}

      game = Games.end_night!(game, %{now: @dawn})

      assert game.state == :day
      assert Games.get_player!(p.villager.id, authorize?: false).alive == false

      assert Games.get_action!(seer_action1.id, authorize?: false).result == %{
               "is_werewolf" => true
             }

      assert Games.get_action!(protect1.id, authorize?: false).target_id == p.hunter.id
      assert Games.get_player!(p.hunter.id, authorize?: false).alive == true

      game = Games.end_day!(game, %{now: ~U[2026-06-16 20:00:00Z]})
      night2 = current_phase(game)

      seer_action2 =
        Games.create_action!(night2.id, p.seer.id, p.hunter.id, :investigate,
          actor: actor_for(p.seer)
        )

      assert seer_action2.result == %{"is_werewolf" => false}
    end

    test "hunter path: only the dead, pending hunter may shoot" do
      %{game: game, players: p} = started_game()

      Games.update_player!(p.hunter, %{alive: false})
      game = force_state(game, :hunter_pending)
      day = current_phase(game)

      shot =
        Games.create_action!(day.id, p.hunter.id, p.villager.id, :shoot,
          actor: actor_for(p.hunter)
        )

      assert shot.type == :shoot

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =
               Games.create_action(day.id, p.villager.id, p.werewolf.id, :shoot,
                 actor: actor_for(p.villager)
               )
    end
  end
end
