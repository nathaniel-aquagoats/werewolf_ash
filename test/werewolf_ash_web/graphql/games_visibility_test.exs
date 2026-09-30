defmodule WerewolfAshWeb.Graphql.GamesVisibilityTest do
  @moduledoc """
  Visibility tests for werewolf_ash-27w.3 (rules 5, 31-33): what a reader's
  own seat lets them see over GraphQL, each paired with the visible
  counterpart so the test would fail if the policy were removed or the
  field were always hidden.
  """

  use WerewolfAshWeb.ConnCase, async: false

  import WerewolfAsh.AnnouncementHelpers, only: [announce_death!: 1]
  import WerewolfAsh.Generators
  import WerewolfAsh.GraphqlHelpers

  alias WerewolfAsh.Games

  @start ~U[2026-06-15 09:30:00Z]
  @dusk ~U[2026-06-15 20:00:00Z]

  setup do
    capture_magic_links!()
    :ok
  end

  @roles_query """
  query Game($id: ID!) {
    game(id: $id) {
      id
      players { id role user { name email } }
    }
  }
  """

  @actions_query """
  query Game($id: ID!) {
    game(id: $id) {
      phases { id kind actions { id type } }
    }
  }
  """

  @performed_actions_query """
  query Game($id: ID!) {
    game(id: $id) {
      players { id performedActions { id type } }
    }
  }
  """

  @vote_tally_query """
  query Game($id: ID!) {
    game(id: $id) {
      phases { id kind voteTally }
    }
  }
  """

  @game_query """
  query Game($id: ID!) { game(id: $id) { id } }
  """

  @my_games_query """
  query { myGames { id } }
  """

  defp named(conn, name) do
    user = generate(user(name: name))
    %{user: user, conn: sign_in_as(conn, user), seat: nil}
  end

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

  defp player_role(response, seat_id) do
    response["data"]["game"]["players"]
    |> Enum.find(&(&1["id"] == seat_id))
    |> Map.fetch!("role")
  end

  defp forbidden_field_errors(response) do
    Enum.filter(response["errors"] || [], &(&1["code"] == "forbidden_field"))
  end

  describe "Player.role" do
    test "a wolf's role is hidden from a villager, visible to a fellow wolf, visible once finished, visible to a dead reader" do
      %{game: game, villager: villager, werewolf: werewolf} = started_game(build_conn())

      response = gql(villager.conn, @roles_query, %{"id" => game.id})

      assert player_role(response, werewolf.seat.id) == nil
      assert player_role(response, villager.seat.id) == "villager"
      assert forbidden_field_errors(response) != []
      assert response["data"]["game"]["id"] == game.id

      wolf_response = gql(werewolf.conn, @roles_query, %{"id" => game.id})
      assert player_role(wolf_response, werewolf.seat.id) == "werewolf"

      Games.finish_game!(game, :village, authorize?: false)
      finished_response = gql(villager.conn, @roles_query, %{"id" => game.id})
      assert player_role(finished_response, werewolf.seat.id) == "werewolf"

      Games.update_player!(villager.seat, %{alive: false})
      dead_response = gql(villager.conn, @roles_query, %{"id" => game.id})
      assert player_role(dead_response, werewolf.seat.id) == "werewolf"
    end

    test "the seer's role is hidden from a living werewolf" do
      %{game: game, seer: seer, werewolf: werewolf} = started_game(build_conn())

      response = gql(werewolf.conn, @roles_query, %{"id" => game.id})

      assert player_role(response, seer.seat.id) == nil
      assert player_role(response, werewolf.seat.id) == "werewolf"
    end
  end

  describe "User.email (rule 5)" do
    test "another player's email is null while name is present; the caller's own email is present" do
      %{game: game, villager: villager, werewolf: werewolf} = started_game(build_conn())

      response = gql(villager.conn, @roles_query, %{"id" => game.id})

      players = response["data"]["game"]["players"]
      werewolf_entry = Enum.find(players, &(&1["id"] == werewolf.seat.id))
      villager_entry = Enum.find(players, &(&1["id"] == villager.seat.id))

      assert werewolf_entry["user"]["email"] == nil
      assert is_binary(werewolf_entry["user"]["name"])
      assert villager_entry["user"]["email"] == to_string(villager.user.email)

      assert response["data"]["game"]["id"] == game.id
      assert players != []
    end
  end

  describe "Action rows in phases { actions } (rule 31)" do
    test "a :kill row is absent for a villager, present for a werewolf, present for a dead villager" do
      %{game: game, villager: villager, werewolf: werewolf, bodyguard: bodyguard} =
        started_game(build_conn())

      night = Games.end_day!(game, %{now: @dusk}) |> current_phase()
      # Targets the bodyguard, not the villager reader, so the villager's
      # own seat stays alive for the "still hidden while living" assertion
      # below - being the kill's own victim would otherwise put them under
      # the dead-reader exception instead.
      Games.create_kill_action!(night.id, werewolf.seat.id, bodyguard.seat.id, authorize?: false)

      villager_view = gql(villager.conn, @actions_query, %{"id" => game.id})
      wolf_view = gql(werewolf.conn, @actions_query, %{"id" => game.id})

      refute has_action_type?(villager_view, "kill")
      assert has_action_type?(wolf_view, "kill")

      Games.update_player!(villager.seat, %{alive: false})
      dead_view = gql(villager.conn, @actions_query, %{"id" => game.id})
      assert has_action_type?(dead_view, "kill")
    end

    test "an :investigate row is absent for a wolf and a villager, present for the seer and a dead reader" do
      %{game: game, seer: seer, villager: villager, werewolf: werewolf} =
        started_game(build_conn())

      night = Games.end_day!(game, %{now: @dusk}) |> current_phase()

      Games.create_action!(night.id, seer.seat.id, werewolf.seat.id, :investigate,
        authorize?: false
      )

      refute has_action_type?(
               gql(werewolf.conn, @actions_query, %{"id" => game.id}),
               "investigate"
             )

      refute has_action_type?(
               gql(villager.conn, @actions_query, %{"id" => game.id}),
               "investigate"
             )

      assert has_action_type?(gql(seer.conn, @actions_query, %{"id" => game.id}), "investigate")

      Games.update_player!(villager.seat, %{alive: false})

      assert has_action_type?(
               gql(villager.conn, @actions_query, %{"id" => game.id}),
               "investigate"
             )
    end

    test "a :protect row is absent for everyone but the bodyguard" do
      %{game: game, bodyguard: bodyguard, villager: villager} = started_game(build_conn())

      day = current_phase(game)

      Games.create_action!(day.id, bodyguard.seat.id, villager.seat.id, :protect,
        authorize?: false
      )

      refute has_action_type?(gql(villager.conn, @actions_query, %{"id" => game.id}), "protect")
      assert has_action_type?(gql(bodyguard.conn, @actions_query, %{"id" => game.id}), "protect")
    end

    test "the same :kill row is absent from a villager's view of the wolf's performedActions (rule 32)" do
      %{game: game, villager: villager, werewolf: werewolf, bodyguard: bodyguard} =
        started_game(build_conn())

      night = Games.end_day!(game, %{now: @dusk}) |> current_phase()
      Games.create_kill_action!(night.id, werewolf.seat.id, bodyguard.seat.id, authorize?: false)

      response = gql(villager.conn, @performed_actions_query, %{"id" => game.id})

      wolf_entry =
        response["data"]["game"]["players"] |> Enum.find(&(&1["id"] == werewolf.seat.id))

      refute Enum.any?(wolf_entry["performedActions"], &(&1["type"] == "kill"))
    end
  end

  describe "voteTally (rule 31)" do
    test "a living reader omits another voter's non-counting vote and keeps their own; a dead reader sees both; a no-seat caller gets {}" do
      %{game: game, villager: villager, werewolf: werewolf, seer: seer} =
        started_game(build_conn())

      day = current_phase(game)

      Games.create_action!(day.id, villager.seat.id, werewolf.seat.id, :vote, authorize?: false)
      Games.create_action!(day.id, seer.seat.id, werewolf.seat.id, :vote, authorize?: false)
      announce_death!(Games.update_player!(seer.seat, %{alive: false}))

      living_response = gql(villager.conn, @vote_tally_query, %{"id" => game.id})
      living_tally = fetch_vote_tally(living_response, day.id)

      assert Map.has_key?(living_tally, werewolf.seat.id)
      refute Enum.any?(living_tally[werewolf.seat.id], &(&1["voter_id"] == seer.seat.id))
      assert Enum.any?(living_tally[werewolf.seat.id], &(&1["voter_id"] == villager.seat.id))

      Games.update_player!(villager.seat, %{alive: false})
      dead_response = gql(villager.conn, @vote_tally_query, %{"id" => game.id})
      dead_tally = fetch_vote_tally(dead_response, day.id)

      assert Enum.any?(dead_tally[werewolf.seat.id], &(&1["voter_id"] == seer.seat.id))
      assert Enum.any?(dead_tally[werewolf.seat.id], &(&1["voter_id"] == villager.seat.id))

      outsider = named(build_conn(), "Outsider")
      assert gql(outsider.conn, @game_query, %{"id" => game.id})["data"]["game"] == nil
    end
  end

  describe "no seat (rules 6, 7)" do
    test "game(id) and myGames both come back empty, with no errors entry" do
      %{game: game} = started_game(build_conn())
      outsider = named(build_conn(), "Outsider")

      response = gql(outsider.conn, @game_query, %{"id" => game.id})
      assert response["data"]["game"] == nil
      assert response["errors"] == nil

      my_games_response = gql(outsider.conn, @my_games_query)
      assert my_games_response["data"]["myGames"] == []
      assert my_games_response["errors"] == nil
    end
  end

  test "Phase.summary is not a field: a query selecting it is rejected" do
    %{game: game, owner: owner} = started_game(build_conn())

    query = """
    query Game($id: ID!) {
      game(id: $id) { phases { id summary } }
    }
    """

    response = gql(owner.conn, query, %{"id" => game.id})
    assert response["data"] == nil
    assert [_error] = response["errors"]
  end

  defp current_phase(game) do
    Games.get_game!(game.id, load: :current_phase, authorize?: false).current_phase
  end

  defp has_action_type?(response, type) do
    response["data"]["game"]["phases"]
    |> Enum.flat_map(& &1["actions"])
    |> Enum.any?(&(&1["type"] == type))
  end

  defp fetch_vote_tally(response, phase_id) do
    response["data"]["game"]["phases"]
    |> Enum.find(&(&1["id"] == phase_id))
    |> Map.fetch!("voteTally")
    |> Jason.decode!()
  end
end
