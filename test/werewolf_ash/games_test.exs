defmodule WerewolfAsh.GamesTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias AshStateMachine.Errors.NoMatchingTransition
  alias WerewolfAsh.Games

  # A stand-in actor is enough for ActorIsOwner, which only compares `id`.
  defp update_settings!(game, params) do
    Games.update_game_settings!(game, params, actor: %{id: game.owner_id})
  end

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

      # create_game seats the owner too, so the owner's seat leads the list.
      assert Enum.map(game.players, & &1.user_id) == [owner.id, alice.id, bob.id]

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

      # no `players` argument still seats exactly one player: the owner.
      assert [player] = Games.get_game!(game.id, load: :players).players
      assert player.user_id == owner.id
      assert is_nil(player.role)
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

    test "a nameless owner cannot create a game; a named owner can" do
      nameless = generate(user(name: nil))

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Games.create_game(%{
                 name: "No Name",
                 join_code: "NAME#{System.unique_integer([:positive])}",
                 owner_id: nameless.id
               })

      assert %{fields: [:name]} = error

      named = generate(user(name: "Owner"))

      assert %{owner_id: owner_id} =
               Games.create_game!(%{
                 name: "Has Name",
                 join_code: "NAME#{System.unique_integer([:positive])}",
                 owner_id: named.id
               })

      assert owner_id == named.id
    end

    test "a nameless co-player in the players list fails the whole call, owner included" do
      owner = generate(user(name: "Owner"))
      nameless = generate(user(name: nil))

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Games.create_game(%{
                 name: "Bad Co-Player",
                 join_code: "NAME#{System.unique_integer([:positive])}",
                 owner_id: owner.id,
                 players: [%{user_id: nameless.id}]
               })

      assert %{fields: [:name]} = error
    end
  end

  describe "phase transitions" do
    # 2026-06-15 is an ordinary summer day: London is BST (UTC+1), New York EDT (UTC-4).

    # `start` now needs an owner actor and at least 5 seated players (rules
    # 8-9); seats 4 more players alongside the game's own auto-seated owner
    # and hands back both so the caller can pass `actor: owner`.
    defp ready(opts \\ []) do
      owner = generate(user())
      game = generate(game(Keyword.put(opts, :owner_id, owner.id)))
      generate_many(player(game_id: game.id), 4)
      %{game: game, owner: owner}
    end

    test "walk lobby -> day -> night -> day on the game's local clock (London)" do
      %{game: game, owner: owner} =
        ready(timezone: "Europe/London", day_start: ~T[08:00:00], day_end: ~T[20:00:00])

      # 10:30 BST is daytime, so the first phase is a day ending at 20:00 BST.
      game = Games.start_game!(game, %{now: ~U[2026-06-15 09:30:00Z]}, actor: owner)
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
      %{game: game, owner: owner} =
        ready(timezone: "America/New_York", day_start: ~T[07:30:00], day_end: ~T[19:30:00])

      # 23:00 EDT on the 15th
      game = Games.start_game!(game, %{now: ~U[2026-06-16 03:00:00Z]}, actor: owner)
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
      %{game: game, owner: owner} = ready()

      game = Games.start_game!(game, %{now: ~U[2026-06-15 05:00:00Z]}, actor: owner)
      assert game.state == :night
      assert game.phase_ends_at == ~U[2026-06-15 08:00:00.000000Z]
    end

    test "a transition made exactly on a boundary schedules the following one" do
      %{game: game, owner: owner} = ready()

      # exactly day_start: day, ending at day_end today
      game = Games.start_game!(game, %{now: ~U[2026-06-15 08:00:00Z]}, actor: owner)
      assert game.state == :day
      assert game.phase_ends_at == ~U[2026-06-15 20:00:00.000000Z]

      # exactly day_end: night, ending at day_start tomorrow
      game = Games.end_day!(game, %{now: ~U[2026-06-15 20:00:00Z]})
      assert game.phase_ends_at == ~U[2026-06-16 08:00:00.000000Z]
    end

    test "boundaries follow the local clock across a DST change" do
      # London springs forward at 01:00 UTC on 2026-03-29.
      %{game: game, owner: owner} = ready(timezone: "Europe/London")

      game = Games.start_game!(game, %{now: ~U[2026-03-28 08:00:00Z]}, actor: owner)
      assert game.phase_ends_at == ~U[2026-03-28 20:00:00.000000Z]

      # 08:00 BST is 07:00 UTC: an eleven-hour night.
      game = Games.end_day!(game, %{now: ~U[2026-03-28 20:00:00Z]})
      assert game.phase_ends_at == ~U[2026-03-29 07:00:00.000000Z]
    end

    test "a boundary in a DST gap or overlap resolves to a single instant" do
      # New York springs forward at 02:00 EST on 2026-03-08, so 02:30 does not
      # exist that day: the night ends at the first instant after the gap.
      %{game: game, owner: owner} =
        ready(timezone: "America/New_York", day_start: ~T[02:30:00], day_end: ~T[14:00:00])

      game = Games.start_game!(game, %{now: ~U[2026-03-08 00:00:00Z]}, actor: owner)
      assert game.state == :night
      assert game.phase_ends_at == ~U[2026-03-08 07:00:00.000000Z]

      # It falls back at 02:00 EDT on 2026-11-01, so 01:30 happens twice: the
      # first occurrence (still EDT) wins.
      %{game: game, owner: owner} =
        ready(timezone: "America/New_York", day_start: ~T[01:30:00], day_end: ~T[14:00:00])

      game = Games.start_game!(game, %{now: ~U[2026-11-01 00:00:00Z]}, actor: owner)
      assert game.state == :night
      assert game.phase_ends_at == ~U[2026-11-01 05:30:00.000000Z]
    end

    test "now defaults to the current time" do
      %{game: game, owner: owner} = ready()
      before = DateTime.utc_now()

      # `now` stays omitted (that omission is the point of this test); the
      # actor is passed as `opts` in its place.
      game = Games.start_game!(game, actor: owner)

      assert game.state in [:day, :night]
      assert DateTime.compare(game.phase_ends_at, before) == :gt
      assert [%{number: 1, started_at: started_at}] = phases(game)
      assert DateTime.compare(started_at, before) != :lt
    end

    test "rejects transitions that do not match the current state" do
      %{game: game, owner: owner} = ready()
      now = ~U[2026-06-15 12:00:00Z]

      assert {:error, %Ash.Error.Invalid{errors: [%NoMatchingTransition{}]}} =
               Games.end_day(game, %{now: now})

      assert {:error, %Ash.Error.Invalid{errors: [%NoMatchingTransition{}]}} =
               Games.end_night(game, %{now: now})

      game = Games.start_game!(game, %{now: now}, actor: owner)
      assert game.state == :day

      assert {:error, %Ash.Error.Invalid{errors: [%NoMatchingTransition{}]}} =
               Games.start_game(game, %{now: now}, actor: owner)

      assert {:error, %Ash.Error.Invalid{errors: [%NoMatchingTransition{}]}} =
               Games.end_night(game, %{now: now})

      # a rejected transition writes nothing
      assert Games.get_game!(game.id).state == :day
      assert [%{number: 1, kind: :day, ended_at: nil}] = phases(game)
    end

    test "requires the owner as actor, and leaves every player roleless" do
      %{game: game, owner: owner} = ready()
      stranger = generate(user())

      assert {:error, %Ash.Error.Invalid{errors: [error]}} = Games.start_game(game)
      assert %Ash.Error.Changes.InvalidAttribute{field: :owner_id} = error

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Games.start_game(game, %{}, actor: stranger)

      assert %Ash.Error.Changes.InvalidAttribute{field: :owner_id} = error

      assert Games.get_game!(game.id).state == :lobby

      for player <- Games.list_players!(query: [filter: [game_id: game.id]]) do
        assert is_nil(player.role)
      end
    end

    test "requires at least 5 seated players" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))
      generate_many(player(game_id: game.id), 3)

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Games.start_game(game, %{}, actor: owner)

      # `:players` is not a real attribute/argument, so Ash reports it as
      # InvalidChanges (a `fields` list) rather than InvalidAttribute.
      assert %Ash.Error.Changes.InvalidChanges{fields: [:players]} = error
      assert Games.get_game!(game.id).state == :lobby
    end

    test "refuses a configuration the seated players cannot satisfy (rule 9)" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))
      # game() seats the owner, so 2 more reaches 3 total: 3 specials + 1 wolf > 3.
      generate_many(player(game_id: game.id), 2)
      game = update_settings!(game, %{min_players: 3})

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Games.start_game(game, %{}, actor: owner)

      assert %Ash.Error.Changes.InvalidChanges{fields: [:players]} = error

      # no roles are dealt when this fires
      assert Games.list_players!(query: [filter: [game_id: game.id]])
             |> Enum.all?(&is_nil(&1.role))
    end

    test "deals exactly one role to every seated player once the owner starts the game" do
      %{game: game, owner: owner} = ready()

      game = Games.start_game!(game, actor: owner)
      assert game.state in [:day, :night]

      roles =
        Games.list_players!(query: [filter: [game_id: game.id]])
        |> Enum.map(& &1.role)
        |> Enum.frequencies()

      assert roles == %{seer: 1, bodyguard: 1, hunter: 1, werewolf: 1, villager: 1}
    end

    defp phases(game) do
      Games.list_phases!(query: [filter: [game_id: game.id], sort: [number: :asc]])
    end
  end

  describe "day vote resolution (werewolf_ash-qss.5)" do
    # Seats an owner + 4 more players, starts the game at 09:30 UTC so it
    # lands in a day phase (Etc/UTC, 08:00/20:00 windows), and returns the
    # game plus every player keyed by their dealt role.
    defp started_day_game do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))
      generate_many(player(game_id: game.id), 4)
      game = Games.start_game!(game, %{now: ~U[2026-06-15 09:30:00Z]}, actor: owner)

      players =
        Games.list_players!(query: [filter: [game_id: game.id]])
        |> Map.new(&{&1.role, &1})

      %{game: game, players: players}
    end

    defp open_day_phase(game), do: Games.get_game!(game.id, load: :current_phase).current_phase

    test "a plurality lynch that does not end the game: the target dies and the game moves to night (rules 6, 15)" do
      %{game: game, players: p} = started_day_game()
      day = open_day_phase(game)

      Games.create_action!(day.id, p.seer.id, p.villager.id, :vote)
      Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :vote)

      game = Games.end_day!(game, %{now: ~U[2026-06-15 20:00:00Z]})

      assert game.state == :night
      assert Games.get_player!(p.villager.id).alive == false
    end

    test "a plurality lynch that removes the last living wolf finishes the game (rules 6, 12, 13, 14)" do
      %{game: game, players: p} = started_day_game()
      day = open_day_phase(game)

      Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote)
      Games.create_action!(day.id, p.seer.id, p.werewolf.id, :vote)

      game = Games.end_day!(game, %{now: ~U[2026-06-15 20:00:00Z]})

      assert game.state == :finished
      assert game.winner == :village
      assert Games.get_player!(p.werewolf.id).alive == false

      game_phases = Games.list_phases!(query: [filter: [game_id: game.id]])
      refute Enum.any?(game_phases, &is_nil(&1.ended_at))
      refute Enum.any?(game_phases, &(&1.kind == :night))
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

      # the game's own owner is already seated, so this is the second player.
      assert Games.list_players!(query: [filter: [game_id: game.id]]) |> length() == 2

      Games.remove_player!(player)

      assert Games.list_players!(query: [filter: [game_id: game.id]]) |> Enum.map(& &1.user_id) ==
               [game.owner_id]
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

    test "rejects role as an unrecognized input", %{game: game} do
      alice = generate(user())

      assert {:error, %Ash.Error.Invalid{}} = Games.add_player(game.id, alice.id, %{role: :seer})
    end

    test "a seat can be given up while the game is in the lobby", %{game: game} do
      player = Games.add_player!(game.id, generate(user()).id)

      assert Games.remove_player(player) == :ok
      assert {:error, %Ash.Error.Invalid{}} = Games.get_player(player.id)
    end

    test "a seat cannot be given up once the game has left the lobby" do
      %{game: game, owner: owner} = ready()
      [player | _] = Games.list_players!(query: [filter: [game_id: game.id]])

      Games.start_game!(game, actor: owner)

      assert {:error, %Ash.Error.Invalid{errors: [error]}} = Games.remove_player(player)
      assert %Ash.Error.Changes.InvalidAttribute{field: :game_id} = error
      assert Games.get_player!(player.id).id == player.id
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

    test "refuses to seat a nameless user and creates no player", %{game: game} do
      nameless = generate(user(name: nil))

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Games.add_player(game.id, nameless.id)

      assert %{fields: [:name]} = error
      assert Games.list_players!(query: [filter: [user_id: nameless.id]]) == []
    end

    test "seats a named user, exactly as before this rule existed", %{game: game} do
      named = generate(user(name: "Carl"))

      assert %{user_id: user_id} = Games.add_player!(game.id, named.id)
      assert user_id == named.id
    end

    test "two players may share the identical display name in one game", %{game: game} do
      alice = generate(user(name: "Same Name"))
      bob = generate(user(name: "Same Name"))

      assert %{id: alice_player_id} = Games.add_player!(game.id, alice.id)
      assert %{id: bob_player_id} = Games.add_player!(game.id, bob.id)
      assert alice_player_id != bob_player_id
    end

    test "accepts add_player below max_players (rule 16)", %{game: game} do
      game = update_settings!(game, %{max_players: 4, min_players: 4})
      alice = generate(user())

      assert %{user_id: user_id} = Games.add_player!(game.id, alice.id)
      assert user_id == alice.id
    end

    test "refuses add_player once max_players is already seated (rule 16)", %{game: game} do
      game = update_settings!(game, %{max_players: 4, min_players: 4})
      # game() already seats the owner, so 3 more reaches the cap of 4.
      generate_many(player(game_id: game.id), 3)
      alice = generate(user())

      assert {:error, %Ash.Error.Invalid{errors: errors}} = Games.add_player(game.id, alice.id)

      assert Enum.any?(
               errors,
               &match?(%Ash.Error.Changes.InvalidAttribute{field: :game_id}, &1)
             )

      assert Games.list_players!(query: [filter: [game_id: game.id]]) |> length() == 4
    end

    test "add_player is never refused on max_players when it is nil", %{game: game} do
      generate_many(player(game_id: game.id), 10)
      alice = generate(user())

      assert %{user_id: user_id} = Games.add_player!(game.id, alice.id)
      assert user_id == alice.id
    end
  end

  describe "join_game" do
    test "seats a user in the game named by its join_code" do
      game = generate(game())
      user = generate(user())

      player = Games.join_game!(game.join_code, user.id)

      assert player.user_id == user.id
      assert player.game_id == game.id
      assert is_nil(player.role)
    end

    test "refuses to seat a nameless user and creates no player" do
      game = generate(game())
      nameless = generate(user(name: nil))

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Games.join_game(game.join_code, nameless.id)

      assert %{fields: [:name]} = error
      assert Games.list_players!(query: [filter: [user_id: nameless.id]]) == []
    end

    test "seats a named user via join, exactly as before this rule existed" do
      game = generate(game())
      named = generate(user(name: "Dana"))

      assert %{user_id: user_id} = Games.join_game!(game.join_code, named.id)
      assert user_id == named.id
    end

    test "two players may share the identical display name via join in one game" do
      game = generate(game())
      alice = generate(user(name: "Twin"))
      bob = generate(user(name: "Twin"))

      assert %{id: alice_player_id} = Games.join_game!(game.join_code, alice.id)
      assert %{id: bob_player_id} = Games.join_game!(game.join_code, bob.id)
      assert alice_player_id != bob_player_id
    end

    test "an unknown join_code errors on :join_code and creates no player" do
      user = generate(user())

      assert {:error, %Ash.Error.Invalid{errors: errors}} = Games.join_game("NOPE0000", user.id)

      assert Enum.any?(
               errors,
               &match?(%Ash.Error.Changes.InvalidAttribute{field: :join_code}, &1)
             )
    end

    test "a join_code for a game that has already left the lobby errors on :join_code" do
      %{game: game, owner: owner} = ready()
      Games.start_game!(game, actor: owner)
      user = generate(user())

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Games.join_game(game.join_code, user.id)

      # :join_code is an action argument, not an attribute, so Ash reports
      # this one as InvalidArgument rather than InvalidAttribute.
      assert %Ash.Error.Changes.InvalidArgument{field: :join_code} = error
    end

    test "rejects role as an unrecognized input, the same as add_player" do
      game = generate(game())
      user = generate(user())

      assert {:error, %Ash.Error.Invalid{}} =
               Games.join_game(game.join_code, user.id, %{role: :seer})
    end

    test "joining twice fails the same way as a duplicate add_player seat" do
      game = generate(game())
      user = generate(user())
      Games.join_game!(game.join_code, user.id)

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Games.join_game(game.join_code, user.id)

      assert %Ash.Error.Changes.InvalidAttribute{field: :game_id} = error
    end

    test "accepts a join below max_players (rule 11)" do
      game = generate(game())
      game = update_settings!(game, %{max_players: 4, min_players: 4})
      user = generate(user())

      assert %{user_id: user_id} = Games.join_game!(game.join_code, user.id)
      assert user_id == user.id
    end

    test "refuses a join once max_players is already seated (rule 11)" do
      game = generate(game())
      game = update_settings!(game, %{max_players: 4, min_players: 4})
      # game() already seats the owner, so 3 more reaches the cap of 4.
      generate_many(player(game_id: game.id), 3)
      user = generate(user())

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Games.join_game(game.join_code, user.id)

      assert %Ash.Error.Changes.InvalidArgument{field: :join_code} = error
      assert Games.list_players!(query: [filter: [game_id: game.id]]) |> length() == 4
    end

    test "a join is never refused on max_players when it is nil" do
      game = generate(game())
      generate_many(player(game_id: game.id), 10)
      user = generate(user())

      assert %{user_id: user_id} = Games.join_game!(game.join_code, user.id)
      assert user_id == user.id
    end
  end

  describe "update_game_settings" do
    test "the owner may change any subset of the seven settings while in :lobby" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))

      updated =
        Games.update_game_settings!(game, %{seer_enabled: false, max_players: 6}, actor: owner)

      assert updated.seer_enabled == false
      assert updated.max_players == 6
      # every other setting is left at its default
      assert updated.role_distribution_mode == :automatic
      assert updated.bodyguard_enabled == true
      assert updated.hunter_enabled == true
      assert updated.min_players == 5
    end

    test "rejects a caller other than the game's own owner (rule 2)" do
      owner = generate(user())
      stranger = generate(user())
      game = generate(game(owner_id: owner.id))

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Games.update_game_settings(game, %{max_players: 6}, actor: stranger)

      assert %Ash.Error.Changes.InvalidAttribute{field: :owner_id} = error
      assert is_nil(Games.get_game!(game.id, authorize?: false).max_players)
    end

    test "rejects a change once the game has already left the lobby (rule 3)" do
      %{game: game, owner: owner} = ready()
      game = Games.start_game!(game, actor: owner)

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Games.update_game_settings(game, %{max_players: 10}, actor: owner)

      assert %Ash.Error.Changes.InvalidAttribute{field: :state} = error
    end

    test "rejects nil for any of the five non-nullable settings (rule 1)" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))

      assert {:error, %Ash.Error.Invalid{}} =
               Games.update_game_settings(game, %{role_distribution_mode: nil}, actor: owner)
    end

    test "rejects an attribute outside the seven settings, e.g. name" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))

      assert {:error, %Ash.Error.Invalid{}} =
               Games.update_game_settings(game, %{name: "Renamed"}, actor: owner)
    end

    test "enforces rules 4-7 through the action" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))

      assert has_error?(
               Games.update_game_settings(game, %{min_players: 0}, actor: owner),
               :min_players
             )

      assert has_error?(
               Games.update_game_settings(game, %{max_players: 0}, actor: owner),
               :max_players
             )

      assert has_error?(
               Games.update_game_settings(game, %{min_players: 10, max_players: 5}, actor: owner),
               :max_players
             )

      assert has_error?(
               Games.update_game_settings(game, %{role_distribution_mode: :manual}, actor: owner),
               :manual_werewolf_count
             )

      assert has_error?(
               Games.update_game_settings(
                 game,
                 %{min_players: 1, max_players: 3},
                 actor: owner
               ),
               :max_players
             )

      assert has_error?(
               Games.update_game_settings(
                 game,
                 %{
                   role_distribution_mode: :manual,
                   manual_werewolf_count: 5,
                   min_players: 1,
                   max_players: 4
                 },
                 actor: owner
               ),
               :max_players
             )
    end

    test "rule 17: refuses to set max_players below the seated count" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))
      # game() already seats the owner, so 2 more reaches 3 total.
      generate_many(player(game_id: game.id), 2)

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Games.update_game_settings(
                 game,
                 %{
                   max_players: 2,
                   min_players: 1,
                   seer_enabled: false,
                   bodyguard_enabled: false,
                   hunter_enabled: false
                 },
                 actor: owner
               )

      assert %Ash.Error.Changes.InvalidAttribute{field: :max_players} = error

      assert Games.list_players!(query: [filter: [game_id: game.id]]) |> length() == 3
      reloaded = Games.get_game!(game.id, authorize?: false)
      assert reloaded.max_players == game.max_players
      assert reloaded.min_players == game.min_players
      assert reloaded.seer_enabled == game.seer_enabled
    end

    test "rule 17: setting max_players exactly equal to the seated count is allowed" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))
      generate_many(player(game_id: game.id), 2)

      updated =
        Games.update_game_settings!(
          game,
          %{
            max_players: 3,
            min_players: 3,
            seer_enabled: false,
            bodyguard_enabled: false,
            hunter_enabled: false
          },
          actor: owner
        )

      assert updated.max_players == 3
    end

    test "rule 17: max_players left nil is never refused on this ground" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))
      generate_many(player(game_id: game.id), 10)

      updated = Games.update_game_settings!(game, %{seer_enabled: false}, actor: owner)
      assert is_nil(updated.max_players)
    end

    defp has_error?({:error, %Ash.Error.Invalid{errors: errors}}, field) do
      Enum.any?(errors, &match?(%Ash.Error.Changes.InvalidAttribute{field: ^field}, &1))
    end
  end

  describe "end to end: owner-configured role composition" do
    test "manual mode with a disabled seer deals exactly the configured composition" do
      owner = generate(user())

      game =
        Games.create_game!(%{
          name: "Manual Mode",
          join_code: "MANL#{System.unique_integer([:positive])}",
          owner_id: owner.id
        })

      game =
        Games.update_game_settings!(
          game,
          %{role_distribution_mode: :manual, manual_werewolf_count: 2, seer_enabled: false},
          actor: owner
        )

      [alice, bob, carol, dave] = generate_many(user(), 4)
      Games.join_game!(game.join_code, alice.id)
      Games.join_game!(game.join_code, bob.id)
      Games.add_player!(game.id, carol.id)
      Games.add_player!(game.id, dave.id)

      game = Games.start_game!(game, actor: owner)

      roles =
        Games.list_players!(query: [filter: [game_id: game.id]])
        |> Enum.map(& &1.role)
        |> Enum.frequencies()

      assert roles == %{bodyguard: 1, hunter: 1, werewolf: 2, villager: 1}
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

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :phase_id}]}} =
               Games.create_action(ctx.phase.id, ctx.alice.id, ctx.alice.id, :vote)

      # a different type in the same phase is fine
      Games.update_player!(ctx.alice, %{role: :bodyguard})

      assert %{type: :protect} =
               Games.create_action!(ctx.phase.id, ctx.alice.id, ctx.bob.id, :protect)

      # and so is the same type in another phase
      day2 = Games.create_phase!(ctx.game.id, :day, 2)
      assert %{type: :vote} = Games.create_action!(day2.id, ctx.alice.id, ctx.bob.id, :vote)
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
