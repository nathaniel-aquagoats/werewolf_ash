defmodule WerewolfAsh.Games.AnnouncementTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.AnnouncementHelpers
  import WerewolfAsh.Generators

  alias Ash.Error.Forbidden
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Announcer

  @at ~U[2026-06-15 20:00:00Z]

  describe "Games.create_announcement/2 (rules 1, 2, 4)" do
    test "with authorization on, a seated actor is refused" do
      %{game: game, villager: villager} = day_game()

      assert {:error, %Forbidden{}} =
               Games.create_announcement(
                 %{game_id: game.id, kind: :dawn, announced_at: @at},
                 actor: actor_for(villager)
               )

      assert announcements(game) == []
    end

    test "with authorize?: false it stores kind, deaths, winner, lynch_outcome and night_starting" do
      %{game: game, victim: victim} = day_game()

      assert {:ok, announcement} =
               Games.create_announcement(
                 %{
                   game_id: game.id,
                   kind: :dusk,
                   announced_at: @at,
                   lynch_outcome: :lynched,
                   night_starting: true,
                   winner: nil,
                   deaths: [%{player_id: victim.id, role: :villager, cause: :lynched}]
                 },
                 authorize?: false
               )

      assert announcement.kind == :dusk
      assert announcement.lynch_outcome == :lynched
      assert announcement.night_starting
      assert is_nil(announcement.winner)
      assert [%{player_id: id, role: :villager, cause: :lynched}] = announcement.deaths
      assert id == victim.id
    end

    test "defaults: no deaths, night_starting false" do
      %{game: game} = day_game()

      announcement =
        Games.create_announcement!(%{game_id: game.id, kind: :game_over, announced_at: @at},
          authorize?: false
        )

      assert announcement.deaths == []
      refute announcement.night_starting
    end

    test "destroying the game removes its announcements (rule 1)" do
      game = generate(game())

      Games.create_announcement!(%{game_id: game.id, kind: :dawn, announced_at: @at},
        authorize?: false
      )

      Games.destroy_game!(game, authorize?: false)
      assert Games.list_announcements!(game.id, authorize?: false) == []
    end
  end

  describe "Games.list_announcements/2 (rules 3, 5)" do
    setup do
      ctx = night_game()
      night_kill!(ctx.phase, ctx.wolf, ctx.victim)

      Announcer.announce(ctx.game.id, :dawn, @at, %{
        deaths: Announcer.unannounced_deaths(ctx.game.id)
      })

      ctx
    end

    test "a living seat, a dead seat and a night victim's own seat each read them", ctx do
      for reader <- [ctx.villager, ctx.victim] do
        assert [%{kind: :dawn}] = Games.list_announcements!(ctx.game.id, actor: actor_for(reader))
      end

      Games.update_player!(ctx.villager, %{alive: false})
      assert [_] = Games.list_announcements!(ctx.game.id, actor: actor_for(ctx.villager))
    end

    test "an outsider and no actor get an empty list, not an error", ctx do
      outsider = generate(user())
      assert Games.list_announcements!(ctx.game.id, actor: %{id: outsider.id}) == []
      assert Games.list_announcements!(ctx.game.id, actor: nil) == []
    end

    test "creation order, with game_over last even when created first", ctx do
      # game_over made before the dusk it belongs with, as a winning lynch does.
      Announcer.announce(ctx.game.id, :game_over, @at, %{winner: :village})
      Announcer.announce(ctx.game.id, :dusk, @at, %{lynch_outcome: :no_lynch})

      kinds = ctx.game |> announcements() |> Enum.map(& &1.kind)
      assert kinds == [:dawn, :dusk, :game_over]
    end

    test "order follows creation, not announced_at", ctx do
      Announcer.announce(ctx.game.id, :shot, ~U[2000-01-01 00:00:00Z], %{})
      assert ctx.game |> announcements() |> Enum.map(& &1.kind) == [:dawn, :shot]
    end
  end

  describe "Announcer.unannounced_deaths/1" do
    test "lists exactly the dead, unannounced players with role and cause killed" do
      %{game: game, victim: victim, villager: villager} = day_game()
      Games.update_player!(victim, %{alive: false})
      dead_announced = Games.update_player!(villager, %{alive: false})
      announce_death!(dead_announced)

      assert [%{player_id: id, role: :villager, cause: :killed}] =
               Announcer.unannounced_deaths(game.id)

      assert id == victim.id
    end

    test "is empty when nobody qualifies" do
      %{game: game} = day_game()
      assert Announcer.unannounced_deaths(game.id) == []
    end
  end

  describe "Announcer.announce/4" do
    test "creates the row and marks exactly the listed players announced" do
      %{game: game, victim: victim, villager: villager} = day_game()
      Games.update_player!(victim, %{alive: false})
      Games.update_player!(villager, %{alive: false})

      deaths = [%{player_id: victim.id, role: :villager, cause: :killed}]
      assert {:ok, %{kind: :dawn}} = Announcer.announce(game.id, :dawn, @at, %{deaths: deaths})

      assert [%{kind: :dawn}] = announcements(game)
      assert %{death_announced_at: at} = Games.get_player!(victim.id, authorize?: false)
      assert DateTime.compare(at, @at) == :eq
      assert is_nil(Games.get_player!(villager.id, authorize?: false).death_announced_at)
    end
  end
end
