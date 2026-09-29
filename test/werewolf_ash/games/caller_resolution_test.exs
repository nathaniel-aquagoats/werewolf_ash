defmodule WerewolfAsh.Games.CallerResolutionTest do
  @moduledoc """
  Direct unit tests for the shared caller-resolution module (rules 11-13,
  werewolf_ash-27w.3).
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias Ash.UUID
  alias WerewolfAsh.Games.CallerResolution

  defp actor_for(player), do: %{id: player.user_id}

  describe "resolve_seat/2" do
    test "returns the caller's own seat in the named game" do
      game = generate(game())
      seat = generate(player(game_id: game.id))

      assert {:ok, resolved} = CallerResolution.resolve_seat(game.id, actor_for(seat))
      assert resolved.id == seat.id
    end

    test "fails on :game_id for an unknown game, an unseated caller and no actor" do
      game = generate(game())
      outsider = generate(user())

      assert {:error, error} =
               CallerResolution.resolve_seat(UUID.generate(), %{id: outsider.id})

      assert error.field == :game_id

      assert {:error, error} = CallerResolution.resolve_seat(game.id, %{id: outsider.id})
      assert error.field == :game_id

      assert {:error, error} = CallerResolution.resolve_seat(game.id, nil)
      assert error.field == :game_id
    end
  end

  describe "resolve_seat_and_phase/2" do
    test "returns the caller's own seat and the game's open phase" do
      game = generate(game())
      day = generate(phase(game_id: game.id, kind: :day, number: 1))
      seat = generate(player(game_id: game.id))

      assert {:ok, resolved_seat, resolved_phase} =
               CallerResolution.resolve_seat_and_phase(game.id, actor_for(seat))

      assert resolved_seat.id == seat.id
      assert resolved_phase.id == day.id
    end

    test "fails on :game_id for an unknown game, an unseated caller and no actor" do
      game = generate(game())
      generate(phase(game_id: game.id, kind: :day, number: 1))
      outsider = generate(user())

      assert {:error, error} =
               CallerResolution.resolve_seat_and_phase(UUID.generate(), %{id: outsider.id})

      assert error.field == :game_id

      assert {:error, error} =
               CallerResolution.resolve_seat_and_phase(game.id, %{id: outsider.id})

      assert error.field == :game_id

      assert {:error, error} = CallerResolution.resolve_seat_and_phase(game.id, nil)
      assert error.field == :game_id
    end

    test "fails on :game_id for a lobby or a finished game" do
      lobby_game = generate(game())
      seat = generate(player(game_id: lobby_game.id))

      assert {:error, error} =
               CallerResolution.resolve_seat_and_phase(lobby_game.id, actor_for(seat))

      assert error.field == :game_id

      finished_game = generate(game())
      finished_seat = generate(player(game_id: finished_game.id))

      finished_game
      |> Changeset.for_update(:update, %{}, authorize?: false)
      |> Changeset.force_change_attribute(:state, :finished)
      |> Ash.update!()

      assert {:error, error} =
               CallerResolution.resolve_seat_and_phase(finished_game.id, actor_for(finished_seat))

      assert error.field == :game_id
    end
  end
end
