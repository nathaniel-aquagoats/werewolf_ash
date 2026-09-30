defmodule WerewolfAshWeb.Graphql.AnnouncementsTest do
  @moduledoc """
  werewolf_ash-qss.19 rules 20, 22-24 over GraphQL: the `announcements`
  query, `Player.alive` as the reader sees it, and the schema shape.
  """

  use WerewolfAshWeb.ConnCase, async: false

  import WerewolfAsh.Generators
  import WerewolfAsh.GraphqlHelpers

  alias Ash.UUID
  alias WerewolfAsh.Games
  alias WerewolfAshWeb.GraphqlSchema

  @start ~U[2026-06-15 09:30:00Z]
  @dusk ~U[2026-06-15 20:00:00Z]
  @dawn ~U[2026-06-16 08:00:00Z]

  setup do
    capture_magic_links!()
    :ok
  end

  @announcements_query """
  query A($gameId: ID!) {
    announcements(gameId: $gameId) {
      kind lynchOutcome nightStarting winner
      deaths { playerId role cause }
    }
  }
  """

  @players_query """
  query G($id: ID!) {
    game(id: $id) { mySeat { id alive } players { id alive role } }
  }
  """

  defp named(conn, name) do
    user = generate(user(name: name))
    %{user: user, conn: sign_in_as(conn, user), seat: nil}
  end

  # Five seats with known roles, one wolf kill into the first night.
  defp night_with_victim do
    conn = build_conn()
    owner = named(conn, "Owner")
    villager = named(conn, "Villager")
    wolf = named(conn, "Wolf")
    seer = named(conn, "Seer")
    victim = named(conn, "Victim")
    game = generate(game(owner_id: owner.user.id))

    for %{user: user} <- [villager, wolf, seer, victim] do
      generate(player(game_id: game.id, user_id: user.id))
    end

    game = Games.start_game!(game, %{now: @start}, actor: owner.user)
    seats = Games.list_players!(query: [filter: [game_id: game.id]], authorize?: false)
    by_user = Map.new(seats, &{&1.user_id, &1})

    roles = [
      {owner, :villager},
      {villager, :villager},
      {wolf, :werewolf},
      {seer, :seer},
      {victim, :villager}
    ]

    for {who, role} <- roles, do: Games.update_player!(by_user[who.user.id], %{role: role})

    game = Games.end_day!(game, %{now: @dusk}, authorize?: false)
    night = Games.get_game!(game.id, load: :current_phase, authorize?: false).current_phase
    wolf = %{wolf | seat: by_user[wolf.user.id]}
    victim = %{victim | seat: by_user[victim.user.id]}
    Games.create_kill_action!(night.id, wolf.seat.id, victim.seat.id, authorize?: false)

    %{
      game: game,
      villager: %{villager | seat: by_user[villager.user.id]},
      wolf: wolf,
      victim: victim,
      seer: %{seer | seat: by_user[seer.user.id]}
    }
  end

  defp alive_of(response, seat_id) do
    response["data"]["game"]["players"]
    |> Enum.find(&(&1["id"] == seat_id))
    |> Map.fetch!("alive")
  end

  defp kinds(response), do: Enum.map(response["data"]["announcements"], & &1["kind"])

  describe "announcements(gameId) (rules 3, 23)" do
    test "a living member, the victim and a dead member read them in order" do
      ctx = night_with_victim()
      Games.end_night!(ctx.game, %{now: @dawn}, authorize?: false)
      Games.update_player!(ctx.seer.seat, %{alive: false})

      for who <- [ctx.villager, ctx.victim, ctx.seer] do
        response = gql(who.conn, @announcements_query, %{"gameId" => ctx.game.id})
        assert response["errors"] == nil
        assert kinds(response) == ["dusk", "dawn"]
      end

      response = gql(ctx.villager.conn, @announcements_query, %{"gameId" => ctx.game.id})
      [dusk, dawn] = response["data"]["announcements"]
      assert %{"lynchOutcome" => "no_lynch", "nightStarting" => true} = dusk
      assert [%{"playerId" => id, "role" => "villager", "cause" => "killed"}] = dawn["deaths"]
      assert id == ctx.victim.seat.id
    end

    test "an outsider and a caller with no token get an empty list and no errors" do
      ctx = night_with_victim()
      outsider = named(build_conn(), "Outsider")

      for conn <- [outsider.conn, build_conn()] do
        response = gql(conn, @announcements_query, %{"gameId" => ctx.game.id})
        assert response["errors"] == nil
        assert response["data"]["announcements"] == []
      end

      unknown = gql(outsider.conn, @announcements_query, %{"gameId" => UUID.generate()})
      assert unknown["errors"] == nil
      assert unknown["data"]["announcements"] == []
    end

    test "before dawn no announcement names the victim (rule 22)" do
      ctx = night_with_victim()
      response = gql(ctx.villager.conn, @announcements_query, %{"gameId" => ctx.game.id})

      assert kinds(response) == ["dusk"]
      assert Enum.all?(response["data"]["announcements"], &(&1["deaths"] == []))
    end
  end

  describe "Player.alive and role as the reader sees them (rule 20)" do
    test "a living villager sees the night victim alive and role hidden until dawn, then dead with the role" do
      ctx = night_with_victim()
      vars = %{"id" => ctx.game.id}

      before = gql(ctx.villager.conn, @players_query, vars)
      assert alive_of(before, ctx.victim.seat.id) == true
      victim = Enum.find(before["data"]["game"]["players"], &(&1["id"] == ctx.victim.seat.id))
      assert victim["role"] == nil

      Games.end_night!(ctx.game, %{now: @dawn}, authorize?: false)

      after_dawn = gql(ctx.villager.conn, @players_query, vars)
      assert alive_of(after_dawn, ctx.victim.seat.id) == false
      victim = Enum.find(after_dawn["data"]["game"]["players"], &(&1["id"] == ctx.victim.seat.id))
      assert victim["role"] == "villager"
    end

    test "the victim and a wolf see the truth before dawn" do
      ctx = night_with_victim()
      vars = %{"id" => ctx.game.id}

      for who <- [ctx.victim, ctx.wolf] do
        assert alive_of(gql(who.conn, @players_query, vars), ctx.victim.seat.id) == false
      end
    end

    test "mySeat { alive } follows the same rule" do
      ctx = night_with_victim()
      vars = %{"id" => ctx.game.id}

      assert gql(ctx.victim.conn, @players_query, vars)["data"]["game"]["mySeat"]["alive"] ==
               false

      assert gql(ctx.villager.conn, @players_query, vars)["data"]["game"]["mySeat"]["alive"] ==
               true
    end
  end

  describe "schema shape (rules 20, 23)" do
    @introspection """
    {
      __schema {
        mutationType { fields { name } }
        types { name fields { name args { name } } }
      }
    }
    """

    test "Player.alive takes no argument, deathAnnouncedAt is absent, no announcement mutation" do
      {:ok, %{data: %{"__schema" => schema}}} = Absinthe.run(@introspection, GraphqlSchema)
      player = Enum.find(schema["types"], &(&1["name"] == "Player"))
      field_names = Enum.map(player["fields"], & &1["name"])

      assert "alive" in field_names
      refute "deathAnnouncedAt" in field_names
      refute "visibleAlive" in field_names
      assert Enum.find(player["fields"], &(&1["name"] == "alive"))["args"] == []

      mutation_names = Enum.map(schema["mutationType"]["fields"], & &1["name"])
      refute Enum.any?(mutation_names, &String.contains?(&1, "nnounce"))

      game = Enum.find(schema["types"], &(&1["name"] == "Game"))
      refute "announcements" in Enum.map(game["fields"], & &1["name"])
    end
  end
end
