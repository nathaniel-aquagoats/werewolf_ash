defmodule WerewolfAsh.AnnouncementHelpers do
  @moduledoc """
  Test helpers for werewolf_ash-qss.19: staged games with known roles, and
  marking a death announced without an announcement.
  """

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games

  @doc "Sets the player's private `death_announced_at`, as an announcement listing them would."
  def announce_death!(player, at \\ ~U[2026-06-15 08:00:00Z]) do
    Games.mark_death_announced!(player, %{at: at}, authorize?: false)
  end

  @doc "The actor a player's own user acts as."
  def actor_for(player), do: %{id: player.user_id}

  @doc """
  A game in its first night, open phase included, with a werewolf, seer,
  villager, victim (a villager), hunter and the owner's unroled seat.
  """
  def night_game, do: staged(:night)

  @doc "Like `night_game/0`, but in its first day."
  def day_game, do: staged(:day)

  defp staged(kind) do
    game = force_state!(generate(game()), kind)

    phase = generate(phase(game_id: game.id, kind: kind, number: 1))

    seat = fn role -> generate(player(game_id: game.id, role: role)) end

    %{
      game: game,
      phase: phase,
      wolf: seat.(:werewolf),
      seer: seat.(:seer),
      villager: seat.(:villager),
      victim: seat.(:villager),
      hunter: seat.(:hunter)
    }
  end

  @doc "Every announcement of the game in read order, read as no one (a game rule)."
  def announcements(game) do
    Games.list_announcements!(game.id, authorize?: false)
  end

  @doc "Kills `player` with the wolf's landed kill in `phase`, as a real night kill."
  def night_kill!(phase, wolf, player) do
    Games.create_kill_action!(phase.id, wolf.id, player.id, authorize?: false)
  end

  @doc "Puts the game in `state` directly, bypassing the state machine."
  def force_state!(game, state) do
    game
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:state, state)
    |> Ash.update!()
  end

  @doc "Opens the game's hunter window on `hunter`, as a hunter's death would."
  def pending_hunter!(game, hunter, deadline \\ ~U[2026-06-15 21:00:00Z]) do
    game
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:pending_hunter_id, hunter.id)
    |> Changeset.force_change_attribute(:hunter_deadline_at, deadline)
    |> Ash.update!()
  end

  @doc "Kills every given player outright (`update_player`), so none is announced."
  def kill_all!(players) do
    Enum.each(players, &Games.update_player!(&1, %{alive: false}, authorize?: false))
  end

  @doc "The announcements of one kind."
  def of_kind(game, kind), do: game |> announcements() |> Enum.filter(&(&1.kind == kind))
end
