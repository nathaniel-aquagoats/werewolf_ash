defmodule WerewolfAshWeb.Graphql.GamesTest do
  @moduledoc """
  GraphQL tests for werewolf_ash-27w.3's lobby and in-game mutations and
  reads, through `/gql` as a signed-in player. Games are staged through the
  domain (`WerewolfAsh.Generators`); every mutation is exercised as a
  GraphQL request carrying only game ids and target ids.
  """

  use WerewolfAshWeb.ConnCase, async: false

  import WerewolfAsh.Generators
  import WerewolfAsh.GraphqlHelpers

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @start ~U[2026-06-15 09:30:00Z]
  @dusk ~U[2026-06-15 20:00:00Z]

  setup do
    capture_magic_links!()
    :ok
  end

  @create_game """
  mutation CreateGame($name: String!) {
    createGame(name: $name) {
      result { id joinCode mySeat { id } }
      errors { message fields code }
    }
  }
  """

  @create_game_windowed """
  mutation CreateGame($name: String!, $dayStart: Time, $dayEnd: Time) {
    createGame(name: $name, dayStart: $dayStart, dayEnd: $dayEnd) {
      result { id joinCode }
      errors { message fields code }
    }
  }
  """

  @join_game """
  mutation JoinGame($joinCode: String!) {
    joinGame(joinCode: $joinCode) { id gameId }
  }
  """

  @leave_game """
  mutation LeaveGame($gameId: ID!) {
    leaveGame(gameId: $gameId)
  }
  """

  @start_game """
  mutation StartGame($id: ID!) {
    startGame(id: $id) {
      result { id state }
      errors { message fields code }
    }
  }
  """

  @update_settings """
  mutation UpdateSettings($id: ID!, $input: UpdateGameSettingsInput) {
    updateGameSettings(id: $id, input: $input) {
      result { minPlayers maxPlayers }
      errors { message fields code }
    }
  }
  """

  @vote """
  mutation Vote($gameId: ID!, $targetId: ID!) {
    vote(gameId: $gameId, targetId: $targetId) {
      result { id targetId }
      errors { message fields code }
    }
  }
  """

  @withdraw_vote """
  mutation WithdrawVote($gameId: ID!) {
    withdrawVote(gameId: $gameId) { result errors { message fields code } }
  }
  """

  @kill """
  mutation Kill($gameId: ID!, $targetId: ID!) {
    kill(gameId: $gameId, targetId: $targetId) {
      result { id targetId }
      errors { message fields code }
    }
  }
  """

  @investigate """
  mutation Investigate($gameId: ID!, $targetId: ID!) {
    investigate(gameId: $gameId, targetId: $targetId) {
      result { id result }
      errors { message fields code }
    }
  }
  """

  @protect """
  mutation Protect($gameId: ID!, $targetId: ID!) {
    protect(gameId: $gameId, targetId: $targetId) {
      result { id targetId }
      errors { message fields code }
    }
  }
  """

  @withdraw_protection """
  mutation WithdrawProtection($gameId: ID!) {
    withdrawProtection(gameId: $gameId) { result errors { message fields code } }
  }
  """

  @shoot """
  mutation Shoot($gameId: ID!, $targetId: ID!) {
    shoot(gameId: $gameId, targetId: $targetId) {
      result { id targetId }
      errors { message fields code }
    }
  }
  """

  @game_query """
  query Game($id: ID!) {
    game(id: $id) { id mySeat { id role } }
  }
  """

  @my_games_query """
  query { myGames { id } }
  """

  defp named(conn, name) do
    user = generate(user(name: name))
    %{user: user, conn: sign_in_as(conn, user), seat: nil}
  end

  defp force_pending_hunter(game, hunter_id) do
    game
    |> Changeset.for_update(:update, %{}, authorize?: false)
    |> Changeset.force_change_attribute(:pending_hunter_id, hunter_id)
    |> Changeset.force_change_attribute(
      :hunter_deadline_at,
      DateTime.add(DateTime.utc_now(), 3600, :second)
    )
    |> Ash.update!()
  end

  # Seats an owner + 4 more named players, starts the game (landing in a
  # day), and pins each seat's role so every describe block can address a
  # specific one. Returns each seat keyed by role, each already carrying its
  # own signed-in conn.
  defp started_game(conn) do
    owner = named(conn, "Owner")
    villager = named(conn, "Villager")
    werewolf = named(conn, "Werewolf")
    seer = named(conn, "Seer")
    bodyguard = named(conn, "Bodyguard")

    game = generate(game(owner_id: owner.user.id))

    for %{user: user} <- [villager, werewolf, seer, bodyguard] do
      generate(player(game_id: game.id, user_id: user.id))
    end

    game = Games.start_game!(game, %{now: @start}, actor: owner.user)

    by_user_id =
      Games.list_players!(query: [filter: [game_id: game.id]], authorize?: false)
      |> Map.new(&{&1.user_id, &1})

    Games.update_player!(by_user_id[owner.user.id], %{role: :villager})
    Games.update_player!(by_user_id[villager.user.id], %{role: :villager})
    Games.update_player!(by_user_id[werewolf.user.id], %{role: :werewolf})
    Games.update_player!(by_user_id[seer.user.id], %{role: :seer})
    Games.update_player!(by_user_id[bodyguard.user.id], %{role: :bodyguard})

    %{
      game: game,
      owner: %{owner | seat: by_user_id[owner.user.id]},
      villager: %{villager | seat: by_user_id[villager.user.id]},
      werewolf: %{werewolf | seat: by_user_id[werewolf.user.id]},
      seer: %{seer | seat: by_user_id[seer.user.id]},
      bodyguard: %{bodyguard | seat: by_user_id[bodyguard.user.id]}
    }
  end

  describe "createGame" do
    test "happy path returns a game with a 6-character joinCode and a non-null mySeat", %{
      conn: conn
    } do
      %{conn: conn} = named(conn, "Creator")

      assert %{
               "data" => %{
                 "createGame" => %{
                   "result" => %{"id" => id, "joinCode" => join_code, "mySeat" => %{"id" => _}},
                   "errors" => []
                 }
               }
             } = gql(conn, @create_game, %{"name" => "A New Game"})

      assert is_binary(id)
      assert String.length(join_code) == 6
    end

    test "no token gives a forbidden error and no game", %{conn: conn} do
      assert %{"data" => %{"createGame" => %{"result" => nil, "errors" => [error]}}} =
               gql(conn, @create_game, %{"name" => "Nobody's Game"})

      assert error["code"] == "forbidden"
    end
  end

  describe "joinGame" do
    test "happy path, also with the code lower-cased", %{conn: conn} do
      owner = named(conn, "Owner")
      game = generate(game(owner_id: owner.user.id, join_code: "MIXED1"))

      joiner = named(conn, "Joiner")

      assert %{"data" => %{"joinGame" => %{"id" => id, "gameId" => game_id}}} =
               gql(joiner.conn, @join_game, %{"joinCode" => "mixed1"})

      assert is_binary(id)
      assert game_id == game.id
    end

    test "an unknown code fails", %{conn: conn} do
      joiner = named(conn, "Joiner")

      response = gql(joiner.conn, @join_game, %{"joinCode" => "NOPE00"})
      assert %{"data" => nil, "errors" => [_error]} = response
    end

    test "no token fails", %{conn: conn} do
      owner = named(conn, "Owner")
      generate(game(owner_id: owner.user.id, join_code: "NOAUTH"))

      response = gql(conn, @join_game, %{"joinCode" => "NOAUTH"})
      assert %{"data" => nil, "errors" => [_error]} = response
    end

    test "a started game is refused", %{conn: conn} do
      %{game: game} = started_game(conn)
      joiner = named(conn, "LateJoiner")

      response = gql(joiner.conn, @join_game, %{"joinCode" => game.join_code})
      assert %{"data" => nil, "errors" => [_error]} = response
    end
  end

  describe "leaveGame" do
    test "happy path", %{conn: conn} do
      owner = named(conn, "Owner")
      game = generate(game(owner_id: owner.user.id))
      leaver = named(conn, "Leaver")
      generate(player(game_id: game.id, user_id: leaver.user.id))

      assert %{"data" => %{"leaveGame" => true}} =
               gql(leaver.conn, @leave_game, %{"gameId" => game.id})
    end

    test "the owner is refused", %{conn: conn} do
      owner = named(conn, "Owner")
      game = generate(game(owner_id: owner.user.id))

      response = gql(owner.conn, @leave_game, %{"gameId" => game.id})
      assert %{"data" => nil, "errors" => [_error]} = response
    end

    test "no token fails", %{conn: conn} do
      owner = named(conn, "Owner")
      game = generate(game(owner_id: owner.user.id))

      response = gql(conn, @leave_game, %{"gameId" => game.id})
      assert %{"data" => nil, "errors" => [_error]} = response
    end

    test "an unseated caller is refused", %{conn: conn} do
      owner = named(conn, "Owner")
      game = generate(game(owner_id: owner.user.id))
      outsider = named(conn, "Outsider")

      response = gql(outsider.conn, @leave_game, %{"gameId" => game.id})
      assert %{"data" => nil, "errors" => [_error]} = response
    end

    test "a started game is refused", %{conn: conn} do
      %{game: game, villager: villager} = started_game(conn)

      response = gql(villager.conn, @leave_game, %{"gameId" => game.id})
      assert %{"data" => nil, "errors" => [_error]} = response
    end
  end

  describe "startGame" do
    test "owner happy path moves the state to day or night", %{conn: conn} do
      owner = named(conn, "Owner")
      game = generate(game(owner_id: owner.user.id))
      for _ <- 1..4, do: generate(player(game_id: game.id))

      assert %{
               "data" => %{
                 "startGame" => %{"result" => %{"state" => state}, "errors" => []}
               }
             } = gql(owner.conn, @start_game, %{"id" => game.id})

      assert state in ["day", "night"]
    end

    test "a seated non-owner is refused", %{conn: conn} do
      owner = named(conn, "Owner")
      game = generate(game(owner_id: owner.user.id))
      non_owner = named(conn, "NonOwner")
      generate(player(game_id: game.id, user_id: non_owner.user.id))
      for _ <- 1..3, do: generate(player(game_id: game.id))

      assert %{"data" => %{"startGame" => %{"result" => nil, "errors" => [error]}}} =
               gql(non_owner.conn, @start_game, %{"id" => game.id})

      assert error["code"] == "forbidden"
    end

    test "no token gives an error", %{conn: conn} do
      owner = named(conn, "Owner")
      game = generate(game(owner_id: owner.user.id))

      assert %{"data" => %{"startGame" => %{"result" => nil, "errors" => [_error]}}} =
               gql(conn, @start_game, %{"id" => game.id})
    end

    test "an unseated caller is refused", %{conn: conn} do
      owner = named(conn, "Owner")
      game = generate(game(owner_id: owner.user.id))
      outsider = named(conn, "Outsider")

      assert %{"data" => %{"startGame" => %{"result" => nil, "errors" => [_error]}}} =
               gql(outsider.conn, @start_game, %{"id" => game.id})
    end
  end

  describe "updateGameSettings" do
    test "owner happy path in the lobby", %{conn: conn} do
      owner = named(conn, "Owner")
      game = generate(game(owner_id: owner.user.id))

      assert %{
               "data" => %{
                 "updateGameSettings" => %{
                   "result" => %{"minPlayers" => 6},
                   "errors" => []
                 }
               }
             } =
               gql(owner.conn, @update_settings, %{
                 "id" => game.id,
                 "input" => %{"minPlayers" => 6}
               })
    end

    test "a non-owner is refused", %{conn: conn} do
      owner = named(conn, "Owner")
      game = generate(game(owner_id: owner.user.id))
      non_owner = named(conn, "NonOwner")
      generate(player(game_id: game.id, user_id: non_owner.user.id))

      assert %{
               "data" => %{
                 "updateGameSettings" => %{"result" => nil, "errors" => [error]}
               }
             } =
               gql(non_owner.conn, @update_settings, %{
                 "id" => game.id,
                 "input" => %{"minPlayers" => 6}
               })

      assert error["code"] == "forbidden"
    end

    test "refused after the game has started", %{conn: conn} do
      %{game: game, owner: owner} = started_game(conn)

      assert %{
               "data" => %{
                 "updateGameSettings" => %{"result" => nil, "errors" => [_error]}
               }
             } =
               gql(owner.conn, @update_settings, %{
                 "id" => game.id,
                 "input" => %{"minPlayers" => 6}
               })
    end
  end

  describe "vote" do
    test "happy path", %{conn: conn} do
      %{game: game, villager: villager, werewolf: werewolf} = started_game(conn)

      assert %{
               "data" => %{
                 "vote" => %{
                   "result" => %{"targetId" => target_id},
                   "errors" => []
                 }
               }
             } =
               gql(villager.conn, @vote, %{"gameId" => game.id, "targetId" => werewolf.seat.id})

      assert target_id == werewolf.seat.id
    end

    test "no token fails", %{conn: conn} do
      %{game: game, werewolf: werewolf} = started_game(conn)

      assert %{"data" => %{"vote" => %{"result" => nil, "errors" => [error]}}} =
               gql(conn, @vote, %{"gameId" => game.id, "targetId" => werewolf.seat.id})

      assert error["code"] == "forbidden"
    end

    test "a caller seated in a different game than the one named", %{conn: conn} do
      %{villager: villager, werewolf: werewolf} = started_game(conn)
      %{game: other_game} = started_game(conn)

      assert %{"data" => %{"vote" => %{"result" => nil, "errors" => [error]}}} =
               gql(villager.conn, @vote, %{
                 "gameId" => other_game.id,
                 "targetId" => werewolf.seat.id
               })

      assert error["fields"] == ["game_id"]
    end

    test "the wrong phase (a vote at night) is refused", %{conn: conn} do
      %{game: game, villager: villager, werewolf: werewolf} = started_game(conn)
      Games.end_day!(game, %{now: @dusk})

      assert %{"data" => %{"vote" => %{"result" => nil, "errors" => [_error]}}} =
               gql(villager.conn, @vote, %{"gameId" => game.id, "targetId" => werewolf.seat.id})
    end

    test "a dead voter is refused", %{conn: conn} do
      %{game: game, villager: villager, werewolf: werewolf} = started_game(conn)
      Games.update_player!(villager.seat, %{alive: false})

      assert %{"data" => %{"vote" => %{"result" => nil, "errors" => [_error]}}} =
               gql(villager.conn, @vote, %{"gameId" => game.id, "targetId" => werewolf.seat.id})
    end

    test "a second vote changes the target, not the row count", %{conn: conn} do
      %{game: game, villager: villager, werewolf: werewolf, seer: seer} = started_game(conn)

      assert %{"data" => %{"vote" => %{"result" => %{"id" => id1}}}} =
               gql(villager.conn, @vote, %{"gameId" => game.id, "targetId" => werewolf.seat.id})

      assert %{"data" => %{"vote" => %{"result" => %{"id" => id2, "targetId" => target_id}}}} =
               gql(villager.conn, @vote, %{"gameId" => game.id, "targetId" => seer.seat.id})

      assert id1 == id2
      assert target_id == seer.seat.id

      assert length(
               Games.list_actions!(
                 query: [filter: [actor_id: villager.seat.id, type: :vote]],
                 authorize?: false
               )
             ) == 1
    end
  end

  describe "withdrawVote" do
    test "deletes the vote", %{conn: conn} do
      %{game: game, villager: villager, werewolf: werewolf} = started_game(conn)
      gql(villager.conn, @vote, %{"gameId" => game.id, "targetId" => werewolf.seat.id})

      assert %{"data" => %{"withdrawVote" => %{"result" => true, "errors" => []}}} =
               gql(villager.conn, @withdraw_vote, %{"gameId" => game.id})

      assert Games.list_actions!(
               query: [filter: [actor_id: villager.seat.id, type: :vote]],
               authorize?: false
             ) == []
    end

    test "no token fails", %{conn: conn} do
      %{game: game} = started_game(conn)

      assert %{"data" => %{"withdrawVote" => %{"result" => nil, "errors" => [_error]}}} =
               gql(conn, @withdraw_vote, %{"gameId" => game.id})
    end

    test "a dead caller is refused", %{conn: conn} do
      %{game: game, villager: villager} = started_game(conn)
      Games.update_player!(villager.seat, %{alive: false})

      assert %{"data" => %{"withdrawVote" => %{"result" => nil, "errors" => [_error]}}} =
               gql(villager.conn, @withdraw_vote, %{"gameId" => game.id})
    end

    test "refused on gameId at night, vote row untouched", %{conn: conn} do
      %{game: game, villager: villager, werewolf: werewolf} = started_game(conn)
      gql(villager.conn, @vote, %{"gameId" => game.id, "targetId" => werewolf.seat.id})
      Games.end_day!(game, %{now: @dusk})

      assert %{"data" => %{"withdrawVote" => %{"result" => nil, "errors" => [error]}}} =
               gql(villager.conn, @withdraw_vote, %{"gameId" => game.id})

      assert error["fields"] == ["game_id"]

      assert [_row] =
               Games.list_actions!(
                 query: [filter: [actor_id: villager.seat.id, type: :vote]],
                 authorize?: false
               )
    end
  end

  describe "kill" do
    test "a werewolf lands it", %{conn: conn} do
      %{game: game, werewolf: werewolf, villager: villager} = started_game(conn)
      Games.end_day!(game, %{now: @dusk})

      assert %{"data" => %{"kill" => %{"result" => %{"id" => id}, "errors" => []}}} =
               gql(werewolf.conn, @kill, %{"gameId" => game.id, "targetId" => villager.seat.id})

      assert is_binary(id)
    end

    test "a villager caller is refused", %{conn: conn} do
      %{game: game, werewolf: werewolf, villager: villager} = started_game(conn)
      Games.end_day!(game, %{now: @dusk})

      assert %{"data" => %{"kill" => %{"result" => nil, "errors" => [_error]}}} =
               gql(villager.conn, @kill, %{"gameId" => game.id, "targetId" => werewolf.seat.id})
    end

    test "a second kill the same night is refused", %{conn: conn} do
      %{game: game, werewolf: werewolf, villager: villager, seer: seer} = started_game(conn)
      Games.end_day!(game, %{now: @dusk})
      gql(werewolf.conn, @kill, %{"gameId" => game.id, "targetId" => villager.seat.id})

      assert %{"data" => %{"kill" => %{"result" => nil, "errors" => [_error]}}} =
               gql(werewolf.conn, @kill, %{"gameId" => game.id, "targetId" => seer.seat.id})
    end

    test "a dead wolf is refused", %{conn: conn} do
      %{game: game, werewolf: werewolf, villager: villager} = started_game(conn)
      Games.end_day!(game, %{now: @dusk})
      Games.update_player!(werewolf.seat, %{alive: false})

      assert %{"data" => %{"kill" => %{"result" => nil, "errors" => [_error]}}} =
               gql(werewolf.conn, @kill, %{"gameId" => game.id, "targetId" => villager.seat.id})
    end

    test "no token fails", %{conn: conn} do
      %{game: game, villager: villager} = started_game(conn)
      Games.end_day!(game, %{now: @dusk})

      assert %{"data" => %{"kill" => %{"result" => nil, "errors" => [_error]}}} =
               gql(conn, @kill, %{"gameId" => game.id, "targetId" => villager.seat.id})
    end
  end

  describe "investigate" do
    test "the seer gets the answer in result", %{conn: conn} do
      %{game: game, seer: seer, werewolf: werewolf} = started_game(conn)
      Games.end_day!(game, %{now: @dusk})

      assert %{"data" => %{"investigate" => %{"result" => %{"result" => result}, "errors" => []}}} =
               gql(seer.conn, @investigate, %{"gameId" => game.id, "targetId" => werewolf.seat.id})

      assert Jason.decode!(result) == %{"is_werewolf" => true}
    end

    test "a non-seer is refused", %{conn: conn} do
      %{game: game, villager: villager, werewolf: werewolf} = started_game(conn)
      Games.end_day!(game, %{now: @dusk})

      assert %{"data" => %{"investigate" => %{"result" => nil, "errors" => [_error]}}} =
               gql(villager.conn, @investigate, %{
                 "gameId" => game.id,
                 "targetId" => werewolf.seat.id
               })
    end

    test "a day-time call is refused", %{conn: conn} do
      %{game: game, seer: seer, werewolf: werewolf} = started_game(conn)

      assert %{"data" => %{"investigate" => %{"result" => nil, "errors" => [_error]}}} =
               gql(seer.conn, @investigate, %{"gameId" => game.id, "targetId" => werewolf.seat.id})
    end

    test "a dead seer is refused", %{conn: conn} do
      %{game: game, seer: seer, werewolf: werewolf} = started_game(conn)
      Games.end_day!(game, %{now: @dusk})
      Games.update_player!(seer.seat, %{alive: false})

      assert %{"data" => %{"investigate" => %{"result" => nil, "errors" => [_error]}}} =
               gql(seer.conn, @investigate, %{"gameId" => game.id, "targetId" => werewolf.seat.id})
    end

    test "a second call is refused", %{conn: conn} do
      %{game: game, seer: seer, werewolf: werewolf, villager: villager} = started_game(conn)
      Games.end_day!(game, %{now: @dusk})
      gql(seer.conn, @investigate, %{"gameId" => game.id, "targetId" => werewolf.seat.id})

      assert %{"data" => %{"investigate" => %{"result" => nil, "errors" => [_error]}}} =
               gql(seer.conn, @investigate, %{"gameId" => game.id, "targetId" => villager.seat.id})
    end
  end

  describe "protect" do
    test "the bodyguard's happy path (day)", %{conn: conn} do
      %{game: game, bodyguard: bodyguard, villager: villager} = started_game(conn)

      assert %{"data" => %{"protect" => %{"result" => %{"id" => id}, "errors" => []}}} =
               gql(bodyguard.conn, @protect, %{
                 "gameId" => game.id,
                 "targetId" => villager.seat.id
               })

      assert is_binary(id)
    end

    test "a non-bodyguard is refused", %{conn: conn} do
      %{game: game, villager: villager, werewolf: werewolf} = started_game(conn)

      assert %{"data" => %{"protect" => %{"result" => nil, "errors" => [_error]}}} =
               gql(villager.conn, @protect, %{"gameId" => game.id, "targetId" => werewolf.seat.id})
    end

    test "the same target two days in a row is refused", %{conn: conn} do
      %{game: game, bodyguard: bodyguard, villager: villager} = started_game(conn)
      gql(bodyguard.conn, @protect, %{"gameId" => game.id, "targetId" => villager.seat.id})

      game = Games.end_day!(game, %{now: @dusk})
      game = Games.end_night!(game, %{now: ~U[2026-06-16 08:00:00Z]})

      assert %{"data" => %{"protect" => %{"result" => nil, "errors" => [_error]}}} =
               gql(bodyguard.conn, @protect, %{
                 "gameId" => game.id,
                 "targetId" => villager.seat.id
               })
    end

    test "a night call is refused", %{conn: conn} do
      %{game: game, bodyguard: bodyguard, villager: villager} = started_game(conn)
      Games.end_day!(game, %{now: @dusk})

      assert %{"data" => %{"protect" => %{"result" => nil, "errors" => [_error]}}} =
               gql(bodyguard.conn, @protect, %{
                 "gameId" => game.id,
                 "targetId" => villager.seat.id
               })
    end

    test "a dead bodyguard is refused", %{conn: conn} do
      %{game: game, bodyguard: bodyguard, villager: villager} = started_game(conn)
      Games.update_player!(bodyguard.seat, %{alive: false})

      assert %{"data" => %{"protect" => %{"result" => nil, "errors" => [_error]}}} =
               gql(bodyguard.conn, @protect, %{
                 "gameId" => game.id,
                 "targetId" => villager.seat.id
               })
    end
  end

  describe "withdrawProtection" do
    test "deletes it in the day", %{conn: conn} do
      %{game: game, bodyguard: bodyguard, villager: villager} = started_game(conn)
      gql(bodyguard.conn, @protect, %{"gameId" => game.id, "targetId" => villager.seat.id})

      assert %{"data" => %{"withdrawProtection" => %{"result" => true, "errors" => []}}} =
               gql(bodyguard.conn, @withdraw_protection, %{"gameId" => game.id})

      assert Games.list_actions!(
               query: [filter: [actor_id: bodyguard.seat.id, type: :protect]],
               authorize?: false
             ) == []
    end

    test "refused at night, row untouched", %{conn: conn} do
      %{game: game, bodyguard: bodyguard, villager: villager} = started_game(conn)
      gql(bodyguard.conn, @protect, %{"gameId" => game.id, "targetId" => villager.seat.id})
      Games.end_day!(game, %{now: @dusk})

      assert %{"data" => %{"withdrawProtection" => %{"result" => nil, "errors" => [error]}}} =
               gql(bodyguard.conn, @withdraw_protection, %{"gameId" => game.id})

      assert error["fields"] == ["game_id"]

      assert [_row] =
               Games.list_actions!(
                 query: [filter: [actor_id: bodyguard.seat.id, type: :protect]],
                 authorize?: false
               )
    end
  end

  describe "shoot" do
    test "the pending hunter's shot lands", %{conn: conn} do
      %{game: game, villager: villager, seer: seer} = started_game(conn)
      hunter = named(conn, "Hunter")
      generate(player(game_id: game.id, user_id: hunter.user.id))

      hunter_seat =
        Games.list_players!(
          query: [filter: [game_id: game.id, user_id: hunter.user.id]],
          authorize?: false
        )
        |> List.first()

      Games.update_player!(hunter_seat, %{role: :hunter, alive: false})
      game = force_pending_hunter(game, hunter_seat.id)

      assert %{"data" => %{"shoot" => %{"result" => %{"id" => id}, "errors" => []}}} =
               gql(hunter.conn, @shoot, %{"gameId" => game.id, "targetId" => villager.seat.id})

      assert is_binary(id)
      refute seer.seat.id == villager.seat.id
    end

    test "a non-hunter is refused", %{conn: conn} do
      %{game: game, villager: villager, werewolf: werewolf} = started_game(conn)
      game = force_pending_hunter(game, werewolf.seat.id)

      assert %{"data" => %{"shoot" => %{"result" => nil, "errors" => [_error]}}} =
               gql(villager.conn, @shoot, %{"gameId" => game.id, "targetId" => werewolf.seat.id})
    end

    test "no pending window is refused", %{conn: conn} do
      %{game: game, villager: villager, werewolf: werewolf} = started_game(conn)

      assert %{"data" => %{"shoot" => %{"result" => nil, "errors" => [_error]}}} =
               gql(villager.conn, @shoot, %{"gameId" => game.id, "targetId" => werewolf.seat.id})
    end

    test "a dead target is refused", %{conn: conn} do
      %{game: game, villager: villager, werewolf: werewolf} = started_game(conn)
      game = force_pending_hunter(game, werewolf.seat.id)
      Games.update_player!(werewolf.seat, %{alive: false})
      Games.update_player!(villager.seat, %{alive: false})

      assert %{"data" => %{"shoot" => %{"result" => nil, "errors" => [_error]}}} =
               gql(werewolf.conn, @shoot, %{"gameId" => game.id, "targetId" => villager.seat.id})
    end
  end

  test "a caller with no open phase (a lobby game) calling vote gets an error on gameId and writes no row",
       %{conn: conn} do
    owner = named(conn, "Owner")
    game = generate(game(owner_id: owner.user.id))
    seat = List.first(Games.list_players!(query: [filter: [game_id: game.id]], authorize?: false))

    assert %{"data" => %{"vote" => %{"result" => nil, "errors" => [error]}}} =
             gql(owner.conn, @vote, %{"gameId" => game.id, "targetId" => seat.id})

    assert error["fields"] == ["game_id"]
    assert Games.list_actions!(authorize?: false) == []
  end

  describe "end to end" do
    test "three or more players sign in, play a round and check myGames", %{conn: conn} do
      owner = named(conn, "E2E Owner")

      # A day window covering (almost) the whole 24h means the game lands in
      # day right after startGame, whatever the real wall-clock time is when
      # this test runs - startGame's own `now` argument is hidden from
      # GraphQL callers (rule 27), so this is the only lever available here.
      assert %{
               "data" => %{
                 "createGame" => %{
                   "result" => %{"id" => game_id, "joinCode" => join_code},
                   "errors" => []
                 }
               }
             } =
               gql(owner.conn, @create_game_windowed, %{
                 "name" => "End to End",
                 "dayStart" => "00:00:01",
                 "dayEnd" => "23:59:59"
               })

      second = named(conn, "E2E Second")
      third = named(conn, "E2E Third")

      for player <- [second, third] do
        assert %{"data" => %{"joinGame" => %{"gameId" => ^game_id}}} =
                 gql(player.conn, @join_game, %{"joinCode" => join_code})
      end

      assert %{
               "data" => %{
                 "updateGameSettings" => %{"result" => %{"minPlayers" => 3}, "errors" => []}
               }
             } =
               gql(owner.conn, @update_settings, %{
                 "id" => game_id,
                 "input" => %{
                   "minPlayers" => 3,
                   "seerEnabled" => false,
                   "bodyguardEnabled" => false,
                   "hunterEnabled" => false
                 }
               })

      assert %{"data" => %{"startGame" => %{"result" => %{"state" => "day"}, "errors" => []}}} =
               gql(owner.conn, @start_game, %{"id" => game_id})

      # Roles are read with game(id) { mySeat { role } }, one call per seat.
      seats =
        for player <- [owner, second, third], into: %{} do
          assert %{"data" => %{"game" => %{"mySeat" => %{"id" => seat_id, "role" => role}}}} =
                   gql(player.conn, @game_query, %{"id" => game_id})

          {player.user.id, %{seat_id: seat_id, role: role, player: player}}
        end

      by_role = Map.new(seats, fn {_user_id, %{role: role} = seat} -> {role, seat} end)
      wolf = by_role["werewolf"]
      villager = Enum.find(Map.values(by_role), &(&1.role != "werewolf"))

      # A villager votes and withdraws (day, GraphQL); only game ids and
      # target ids ever cross the wire.
      assert %{"data" => %{"vote" => %{"result" => %{"id" => _}, "errors" => []}}} =
               gql(villager.player.conn, @vote, %{
                 "gameId" => game_id,
                 "targetId" => wolf.seat_id
               })

      assert %{"data" => %{"withdrawVote" => %{"result" => true, "errors" => []}}} =
               gql(villager.player.conn, @withdraw_vote, %{"gameId" => game_id})

      # The day ends through the domain directly, not GraphQL.
      game = Games.get_game!(game_id, authorize?: false)
      Games.end_day!(game, %{now: @dusk})

      # A wolf kills (now night, GraphQL).
      assert %{"data" => %{"kill" => %{"result" => %{"id" => _}, "errors" => []}}} =
               gql(wolf.player.conn, @kill, %{
                 "gameId" => game_id,
                 "targetId" => villager.seat_id
               })

      assert %{"data" => %{"myGames" => [%{"id" => first_id} | _]}} =
               gql(owner.conn, @my_games_query)

      assert first_id == game_id
    end
  end
end
