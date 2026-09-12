defmodule WerewolfAsh.GamesTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias AshStateMachine.Errors.NoMatchingTransition
  alias WerewolfAsh.Games

  describe "games" do
    test "creates a game with players through the code interface" do
      owner = generate(user())
      [alice, bob] = generate_many(user(), 2)

      game =
        Games.create_game!(%{
          name: "Friday night",
          join_code: "WOLF#{System.unique_integer([:positive])}",
          timezone: "Europe/London",
          day_start: ~T[09:00:00],
          day_end: ~T[21:00:00],
          owner_id: owner.id,
          players: [%{user_id: alice.id}, %{user_id: bob.id}]
        })

      # User carries a policy authorizer, so loading the owner needs authorize?: false here.
      game = Games.get_game!(game.id, load: [:owner, :players], authorize?: false)

      assert game.name == "Friday night"
      assert game.state == :lobby
      assert game.timezone == "Europe/London"
      assert game.day_start == ~T[09:00:00]
      assert game.day_end == ~T[21:00:00]
      assert is_nil(game.phase_ends_at)
      assert game.owner_id == owner.id
      assert game.owner.id == owner.id

      assert Enum.map(game.players, & &1.user_id) == [alice.id, bob.id]

      for player <- game.players do
        assert player.game_id == game.id
        assert player.alive
        assert is_nil(player.role)
        assert %DateTime{} = player.joined_at
      end
    end

    test "applies sensible defaults for windows, timezone and state" do
      owner = generate(user())

      game =
        Games.create_game!(%{
          name: "Defaults",
          join_code: "DFLT#{System.unique_integer([:positive])}",
          owner_id: owner.id
        })

      assert game.timezone == "Etc/UTC"
      assert game.day_start == ~T[08:00:00]
      assert game.day_end == ~T[20:00:00]
      assert game.state == :lobby
      assert Games.get_game!(game.id, load: :players).players == []
    end

    test "looks a game up by its join code" do
      game = generate(game())

      assert Games.get_game_by_join_code!(game.join_code).id == game.id
      assert {:error, %Ash.Error.Invalid{}} = Games.get_game_by_join_code("NOPE0000")
    end

    test "join codes are unique" do
      game = generate(game())

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Games.create_game(%{
                 name: "Copycat",
                 join_code: game.join_code,
                 owner_id: game.owner_id
               })

      assert %Ash.Error.Changes.InvalidAttribute{field: :join_code} = error
    end

    test "updates the day/night windows and timezone" do
      game = generate(game())

      updated =
        Games.update_game!(game, %{
          timezone: "America/New_York",
          day_start: ~T[07:30:00],
          day_end: ~T[19:30:00]
        })

      assert updated.timezone == "America/New_York"
      assert updated.day_start == ~T[07:30:00]
      assert updated.day_end == ~T[19:30:00]
    end

    test "state only accepts known values" do
      game = generate(game())

      assert_raise Ash.Error.Invalid, fn ->
        game
        |> Changeset.for_update(:update, %{})
        |> Changeset.force_change_attribute(:state, :limbo)
        |> Ash.update!()
      end
    end

    test "rejects a timezone the tz database does not know" do
      owner = generate(user())

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Games.create_game(%{
                 name: "Nowhere",
                 join_code: "MARS#{System.unique_integer([:positive])}",
                 timezone: "Mars/Olympus_Mons",
                 owner_id: owner.id
               })

      assert %Ash.Error.Changes.InvalidAttribute{field: :timezone} = error

      game = generate(game())

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :timezone}]}} =
               Games.update_game(game, %{timezone: "Not/A_Zone"})

      assert %{timezone: "Asia/Tokyo"} = Games.update_game!(game, %{timezone: "Asia/Tokyo"})
    end
  end

  describe "phase transitions" do
    # 2026-06-15 is an ordinary summer day: London is BST (UTC+1), New York EDT (UTC-4).

    test "walk lobby -> day -> night -> day on the game's local clock (London)" do
      game =
        generate(game(timezone: "Europe/London", day_start: ~T[08:00:00], day_end: ~T[20:00:00]))

      # 10:30 BST is daytime, so the first phase is a day ending at 20:00 BST.
      game = Games.start_game!(game, %{now: ~U[2026-06-15 09:30:00Z]})
      assert game.state == :day
      assert game.phase_ends_at == ~U[2026-06-15 19:00:00.000000Z]

      assert [
               %{
                 kind: :day,
                 number: 1,
                 started_at: ~U[2026-06-15 09:30:00.000000Z],
                 ended_at: nil
               }
             ] =
               phases(game)

      game = Games.end_day!(game, %{now: ~U[2026-06-15 19:00:00Z]})
      assert game.state == :night
      assert game.phase_ends_at == ~U[2026-06-16 07:00:00.000000Z]

      assert [
               %{number: 1, ended_at: ~U[2026-06-15 19:00:00.000000Z]},
               %{
                 kind: :night,
                 number: 2,
                 started_at: ~U[2026-06-15 19:00:00.000000Z],
                 ended_at: nil
               }
             ] = phases(game)

      game = Games.end_night!(game, %{now: ~U[2026-06-16 07:00:00Z]})
      assert game.state == :day
      assert game.phase_ends_at == ~U[2026-06-16 19:00:00.000000Z]

      assert [
               %{number: 1, kind: :day},
               %{number: 2, kind: :night, ended_at: ~U[2026-06-16 07:00:00.000000Z]},
               %{
                 number: 3,
                 kind: :day,
                 started_at: ~U[2026-06-16 07:00:00.000000Z],
                 ended_at: nil
               }
             ] = phases(game)

      game = Games.get_game!(game.id, load: [:current_phase, :last_phase_number])
      assert game.last_phase_number == 3
      assert %{number: 3, kind: :day} = game.current_phase
    end

    test "a start after dusk lands in night and ends at the next dawn (New York)" do
      game =
        generate(
          game(timezone: "America/New_York", day_start: ~T[07:30:00], day_end: ~T[19:30:00])
        )

      # 23:00 EDT on the 15th
      game = Games.start_game!(game, %{now: ~U[2026-06-16 03:00:00Z]})
      assert game.state == :night
      assert game.phase_ends_at == ~U[2026-06-16 11:30:00.000000Z]
      assert [%{kind: :night, number: 1, ended_at: nil}] = phases(game)

      game = Games.end_night!(game, %{now: ~U[2026-06-16 11:30:00Z]})
      assert game.state == :day
      assert game.phase_ends_at == ~U[2026-06-16 23:30:00.000000Z]

      assert [%{number: 1, ended_at: ~U[2026-06-16 11:30:00.000000Z]}, %{number: 2, kind: :day}] =
               phases(game)
    end

    test "a start before dawn is a night that ends at dawn the same day" do
      game = generate(game())

      game = Games.start_game!(game, %{now: ~U[2026-06-15 05:00:00Z]})
      assert game.state == :night
      assert game.phase_ends_at == ~U[2026-06-15 08:00:00.000000Z]
    end

    test "a transition made exactly on a boundary schedules the following one" do
      game = generate(game())

      # exactly day_start: day, ending at day_end today
      game = Games.start_game!(game, %{now: ~U[2026-06-15 08:00:00Z]})
      assert game.state == :day
      assert game.phase_ends_at == ~U[2026-06-15 20:00:00.000000Z]

      # exactly day_end: night, ending at day_start tomorrow
      game = Games.end_day!(game, %{now: ~U[2026-06-15 20:00:00Z]})
      assert game.phase_ends_at == ~U[2026-06-16 08:00:00.000000Z]
    end

    test "boundaries follow the local clock across a DST change" do
      # London springs forward at 01:00 UTC on 2026-03-29.
      game = generate(game(timezone: "Europe/London"))

      game = Games.start_game!(game, %{now: ~U[2026-03-28 08:00:00Z]})
      assert game.phase_ends_at == ~U[2026-03-28 20:00:00.000000Z]

      # 08:00 BST is 07:00 UTC: an eleven-hour night.
      game = Games.end_day!(game, %{now: ~U[2026-03-28 20:00:00Z]})
      assert game.phase_ends_at == ~U[2026-03-29 07:00:00.000000Z]
    end

    test "a boundary in a DST gap or overlap resolves to a single instant" do
      # New York springs forward at 02:00 EST on 2026-03-08, so 02:30 does not
      # exist that day: the night ends at the first instant after the gap.
      game =
        generate(
          game(timezone: "America/New_York", day_start: ~T[02:30:00], day_end: ~T[14:00:00])
        )

      game = Games.start_game!(game, %{now: ~U[2026-03-08 00:00:00Z]})
      assert game.state == :night
      assert game.phase_ends_at == ~U[2026-03-08 07:00:00.000000Z]

      # It falls back at 02:00 EDT on 2026-11-01, so 01:30 happens twice: the
      # first occurrence (still EDT) wins.
      game =
        generate(
          game(timezone: "America/New_York", day_start: ~T[01:30:00], day_end: ~T[14:00:00])
        )

      game = Games.start_game!(game, %{now: ~U[2026-11-01 00:00:00Z]})
      assert game.state == :night
      assert game.phase_ends_at == ~U[2026-11-01 05:30:00.000000Z]
    end

    test "now defaults to the current time" do
      game = generate(game())
      before = DateTime.utc_now()

      game = Games.start_game!(game)

      assert game.state in [:day, :night]
      assert DateTime.compare(game.phase_ends_at, before) == :gt
      assert [%{number: 1, started_at: started_at}] = phases(game)
      assert DateTime.compare(started_at, before) != :lt
    end

    test "rejects transitions that do not match the current state" do
      game = generate(game())
      now = ~U[2026-06-15 12:00:00Z]

      assert {:error, %Ash.Error.Invalid{errors: [%NoMatchingTransition{}]}} =
               Games.end_day(game, %{now: now})

      assert {:error, %Ash.Error.Invalid{errors: [%NoMatchingTransition{}]}} =
               Games.end_night(game, %{now: now})

      game = Games.start_game!(game, %{now: now})
      assert game.state == :day

      assert {:error, %Ash.Error.Invalid{errors: [%NoMatchingTransition{}]}} =
               Games.start_game(game, %{now: now})

      assert {:error, %Ash.Error.Invalid{errors: [%NoMatchingTransition{}]}} =
               Games.end_night(game, %{now: now})

      # a rejected transition writes nothing
      assert Games.get_game!(game.id).state == :day
      assert [%{number: 1, kind: :day, ended_at: nil}] = phases(game)
    end

    defp phases(game) do
      Games.list_phases!(query: [filter: [game_id: game.id], sort: [number: :asc]])
    end
  end

  describe "players" do
    setup do
      %{game: generate(game())}
    end

    test "adds and removes players one at a time", %{game: game} do
      alice = generate(user())

      player = Games.add_player!(game.id, alice.id)
      assert player.user_id == alice.id
      assert player.game_id == game.id
      assert player.alive
      assert is_nil(player.role)

      assert [%{id: id}] = Games.list_players!(query: [filter: [game_id: game.id]])
      assert id == player.id

      Games.remove_player!(player)
      assert Games.list_players!(query: [filter: [game_id: game.id]]) == []
    end

    test "a user can only hold one seat per game", %{game: game} do
      alice = generate(user())
      Games.add_player!(game.id, alice.id)

      assert {:error, %Ash.Error.Invalid{errors: [error]}} = Games.add_player(game.id, alice.id)
      assert %Ash.Error.Changes.InvalidAttribute{message: "has already been taken"} = error

      other_game = generate(game())
      assert %{user_id: user_id} = Games.add_player!(other_game.id, alice.id)
      assert user_id == alice.id
    end

    test "updates role and aliveness", %{game: game} do
      player = Games.add_player!(game.id, generate(user()).id)

      player = Games.update_player!(player, %{role: :seer})
      assert player.role == :seer

      player = Games.update_player!(player, %{alive: false})
      refute player.alive

      assert {:error, %Ash.Error.Invalid{}} = Games.update_player(player, %{role: :jester})
    end

    test "are deleted along with their game", %{game: game} do
      Games.add_player!(game.id, generate(user()).id)
      Games.destroy_game!(game)

      assert Games.list_players!(query: [filter: [game_id: game.id]]) == []
    end
  end

  describe "phases" do
    setup do
      %{game: generate(game())}
    end

    test "are numbered per game and listed in order", %{game: game} do
      night = Games.create_phase!(game.id, :night, 2)
      day = Games.create_phase!(game.id, :day, 1)

      assert day.kind == :day
      assert %DateTime{} = day.started_at
      assert is_nil(day.ended_at)
      assert is_nil(day.summary)

      assert Games.get_game!(game.id, load: :phases).phases |> Enum.map(& &1.id) ==
               [day.id, night.id]
    end

    test "reject a duplicate number, a non-positive number and unknown kinds", %{game: game} do
      Games.create_phase!(game.id, :day, 1)

      assert {:error, %Ash.Error.Invalid{errors: [%{message: "has already been taken"}]}} =
               Games.create_phase(game.id, :night, 1)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :number}]}} =
               Games.create_phase(game.id, :day, 0)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :kind}]}} =
               Games.create_phase(game.id, :dusk, 3)
    end

    test "can be closed with a summary", %{game: game} do
      phase = Games.create_phase!(game.id, :day, 1)
      ended_at = DateTime.utc_now()

      phase = Games.update_phase!(phase, %{ended_at: ended_at, summary: %{"lynched" => nil}})

      assert phase.ended_at == ended_at
      assert phase.summary == %{"lynched" => nil}
    end
  end

  describe "actions" do
    setup do
      game = generate(game())
      [alice, bob] = for u <- generate_many(user(), 2), do: Games.add_player!(game.id, u.id)
      %{game: game, phase: Games.create_phase!(game.id, :day, 1), alice: alice, bob: bob}
    end

    test "records who did what to whom in a phase", ctx do
      action = Games.create_action!(ctx.phase.id, ctx.alice.id, ctx.bob.id, :vote)

      assert action.type == :vote
      assert is_nil(action.result)

      action = Games.update_action!(action, %{result: %{"counted" => true}})
      assert action.result == %{"counted" => true}

      alice = Games.get_player!(ctx.alice.id, load: [:performed_actions, :targeted_by_actions])
      assert [%{id: id}] = alice.performed_actions
      assert id == action.id
      assert alice.targeted_by_actions == []

      bob = Games.get_player!(ctx.bob.id, load: [:targeted_by_actions])
      assert [%{id: ^id}] = bob.targeted_by_actions

      assert [%{id: ^id}] = Games.get_phase!(ctx.phase.id, load: :actions).actions
    end

    test "allows one action per actor, phase and type", ctx do
      Games.create_action!(ctx.phase.id, ctx.alice.id, ctx.bob.id, :vote)

      assert {:error, %Ash.Error.Invalid{errors: [%{message: "has already been taken"}]}} =
               Games.create_action(ctx.phase.id, ctx.alice.id, ctx.alice.id, :vote)

      # a different type in the same phase is fine
      assert %{type: :protect} =
               Games.create_action!(ctx.phase.id, ctx.alice.id, ctx.bob.id, :protect)

      # and so is the same type in another phase
      night = Games.create_phase!(ctx.game.id, :night, 2)
      assert %{type: :vote} = Games.create_action!(night.id, ctx.alice.id, ctx.bob.id, :vote)
    end

    test "rejects unknown types", ctx do
      assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
               Games.create_action(ctx.phase.id, ctx.alice.id, ctx.bob.id, :dance)
    end

    test "are deleted along with their phase", ctx do
      action = Games.create_action!(ctx.phase.id, ctx.alice.id, ctx.bob.id, :vote)
      Ash.destroy!(ctx.phase)

      assert {:error, %Ash.Error.Invalid{}} = Games.get_action(action.id)
    end
  end
end
