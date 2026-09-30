defmodule WerewolfAsh.Games.AnnouncementsEndToEndTest do
  @moduledoc "werewolf_ash-qss.19: a whole game's announcements through the code interface."

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.AnnouncementHelpers
  import WerewolfAsh.Generators

  alias Ash.ForbiddenField
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Player

  @start ~U[2026-06-15 09:30:00Z]
  @dusk ~U[2026-06-15 20:00:00Z]
  @dawn ~U[2026-06-16 08:00:00Z]
  @dusk2 ~U[2026-06-16 20:00:00Z]

  defp started do
    owner = generate(user())
    game = generate(game(owner_id: owner.id))
    generate_many(player(game_id: game.id), 4)
    game = Games.start_game!(game, %{now: @start}, actor: owner)

    [wolf, seer, villager, victim, other] =
      Games.list_players!(
        query: [filter: [game_id: game.id], sort: [id: :asc]],
        authorize?: false
      )

    roles = [
      wolf: :werewolf,
      seer: :seer,
      villager: :villager,
      victim: :villager,
      other: :villager
    ]

    seats = %{wolf: wolf, seer: seer, villager: villager, victim: victim, other: other}

    seats =
      Map.new(roles, fn {key, role} ->
        {key, Games.update_player!(seats[key], %{role: role}, authorize?: false)}
      end)

    Map.put(seats, :game, game)
  end

  defp current_phase(game) do
    Games.get_game!(game.id, load: :current_phase, authorize?: false).current_phase
  end

  defp read(target, reader) do
    Ash.get!(Player, target.id, load: :visible_alive, actor: actor_for(reader))
  end

  defp kinds(game, reader) do
    game.id |> Games.list_announcements!(actor: actor_for(reader)) |> Enum.map(& &1.kind)
  end

  test "a night, its dawn, and a lynch are announced when they happen, and not before" do
    ctx = started()
    Games.end_day!(ctx.game, %{now: @dusk}, authorize?: false)
    night = current_phase(ctx.game)

    Games.create_kill_action!(night.id, ctx.wolf.id, ctx.victim.id, actor: actor_for(ctx.wolf))

    before_dawn = read(ctx.victim, ctx.villager)
    assert before_dawn.visible_alive
    assert %ForbiddenField{} = before_dawn.role
    assert kinds(ctx.game, ctx.villager) == [:dusk]

    game = Games.get_game!(ctx.game.id, authorize?: false)
    Games.end_night!(game, %{now: @dawn}, authorize?: false)

    assert kinds(ctx.game, ctx.villager) == [:dusk, :dawn]
    [_dusk, dawn] = Games.list_announcements!(ctx.game.id, actor: actor_for(ctx.villager))
    assert [%{player_id: id, role: :villager, cause: :killed}] = dawn.deaths
    assert id == ctx.victim.id

    after_dawn = read(ctx.victim, ctx.villager)
    refute after_dawn.visible_alive
    assert after_dawn.role == :villager

    # the day: the village lynches the wolf's frame-up target
    day = current_phase(ctx.game)

    for voter <- [ctx.villager, ctx.seer] do
      Games.create_action!(day.id, voter.id, ctx.other.id, :vote, actor: actor_for(voter))
    end

    game = Games.get_game!(ctx.game.id, authorize?: false)
    Games.end_day!(game, %{now: @dusk2}, authorize?: false)

    [_dusk, _dawn, dusk2] = Games.list_announcements!(ctx.game.id, actor: actor_for(ctx.villager))
    assert %{kind: :dusk, lynch_outcome: :lynched, night_starting: true} = dusk2
    assert [%{player_id: lynched, role: :villager, cause: :lynched}] = dusk2.deaths
    assert lynched == ctx.other.id
  end

  test "a game won at dusk shows the dusk (night not starting) and then game_over" do
    ctx = started()

    for voter <- [ctx.villager, ctx.seer] do
      Games.create_action!(ctx.game.id |> current_phase_id(), voter.id, ctx.wolf.id, :vote,
        actor: actor_for(voter)
      )
    end

    Games.end_day!(ctx.game, %{now: @dusk}, authorize?: false)

    assert [
             %{kind: :dusk, night_starting: false, lynch_outcome: :lynched},
             %{kind: :game_over, winner: :village}
           ] = Games.list_announcements!(ctx.game.id, actor: actor_for(ctx.seer))

    # a finished game reveals every role without any announcement doing it
    assert read(ctx.other, ctx.villager).role == :villager
  end

  defp current_phase_id(game_id) do
    Games.get_game!(game_id, load: :current_phase, authorize?: false).current_phase.id
  end
end
