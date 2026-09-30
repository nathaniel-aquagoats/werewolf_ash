defmodule WerewolfAsh.Games.Game.Changes.AnnounceDawnTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.AnnouncementHelpers
  import WerewolfAsh.Generators

  alias WerewolfAsh.Games

  @now ~U[2026-06-16 08:00:00Z]

  test "lists the night victim with role and cause killed, at the action's now, and marks them" do
    %{game: game, phase: night, wolf: wolf, victim: victim} = night_game()
    night_kill!(night, wolf, victim)

    Games.end_night!(game, %{now: @now}, authorize?: false)

    assert [dawn] = of_kind(game, :dawn)
    assert [%{player_id: id, role: :villager, cause: :killed}] = dawn.deaths
    assert id == victim.id
    assert DateTime.compare(dawn.announced_at, @now) == :eq
    refute dawn.night_starting
    assert is_nil(dawn.lynch_outcome)
    refute is_nil(Games.get_player!(victim.id, authorize?: false).death_announced_at)
  end

  test "is still announced, empty, when nobody died" do
    %{game: game} = night_game()

    Games.end_night!(game, %{now: @now}, authorize?: false)

    assert [%{deaths: []}] = of_kind(game, :dawn)
  end

  test "is empty when the bodyguard saved the target" do
    game = force_state!(generate(game()), :night)
    day = generate(phase(game_id: game.id, kind: :day, number: 1))
    night = generate(phase(game_id: game.id, kind: :night, number: 2))
    wolf = generate(player(game_id: game.id, role: :werewolf))
    bodyguard = generate(player(game_id: game.id, role: :bodyguard))
    target = generate(player(game_id: game.id, role: :villager))
    generate_many(player(game_id: game.id, role: :villager), 2)
    Games.create_action!(day.id, bodyguard.id, target.id, :protect, authorize?: false)
    night_kill!(night, wolf, target)

    Games.end_night!(Games.get_game!(game.id, authorize?: false), %{now: @now}, authorize?: false)

    assert [%{deaths: []}] = of_kind(game, :dawn)
  end

  test "never lists a player an earlier announcement already named" do
    %{game: game, victim: victim, villager: villager} = night_game()
    kill_all!([victim, villager])
    announce_death!(Games.get_player!(victim.id, authorize?: false))

    Games.end_night!(game, %{now: @now}, authorize?: false)

    assert [%{deaths: [%{player_id: id}]}] = of_kind(game, :dawn)
    assert id == villager.id
  end

  test "is still produced when the dawn win check finished the game" do
    %{game: game, seer: seer, villager: villager, victim: victim, hunter: hunter} = night_game()
    kill_all!([seer, villager, victim, hunter])
    owner = Games.list_players!(query: [filter: [game_id: game.id, role: nil]], authorize?: false)
    kill_all!(owner)

    Games.end_night!(game, %{now: @now}, authorize?: false)

    assert Games.get_game!(game.id, authorize?: false).state == :finished
    assert [%{deaths: [_ | _]}] = of_kind(game, :dawn)
    assert [%{winner: :wolves}] = of_kind(game, :game_over)
  end
end
