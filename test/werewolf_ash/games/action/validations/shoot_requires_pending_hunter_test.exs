defmodule WerewolfAsh.Games.Action.Validations.ShootRequiresPendingHunterTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias Ash.UUID
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Action.Validations.ShootRequiresPendingHunter

  defp force_pending_hunter(game, hunter_id) do
    game
    |> Changeset.for_update(:update, %{})
    |> Changeset.force_change_attribute(:pending_hunter_id, hunter_id)
    |> Changeset.force_change_attribute(:hunter_deadline_at, DateTime.utc_now())
    |> Ash.update!()
  end

  defp actor_id_changeset(actor_id) do
    %Action{}
    |> Changeset.new()
    |> Changeset.change_attribute(:actor_id, actor_id)
  end

  describe "validate/3" do
    test "passes for the player the game's pointer names" do
      game = generate(game())
      hunter = generate(player(game_id: game.id, role: :hunter))
      force_pending_hunter(game, hunter.id)

      assert ShootRequiresPendingHunter.validate(actor_id_changeset(hunter.id), [], %{}) == :ok
    end

    test "fails, on :actor_id, for a different player than the one the pointer names" do
      game = generate(game())
      hunter = generate(player(game_id: game.id, role: :hunter))
      villager = generate(player(game_id: game.id, role: :villager))
      force_pending_hunter(game, hunter.id)

      assert {:error, error} =
               ShootRequiresPendingHunter.validate(actor_id_changeset(villager.id), [], %{})

      assert Keyword.fetch!(error, :field) == :actor_id
    end

    test "fails, on :actor_id, when the game's pointer is nil" do
      game = generate(game())
      hunter = generate(player(game_id: game.id, role: :hunter))
      # `game` is never given a pending_hunter_id: the pointer stays nil.
      _ = game

      assert {:error, error} =
               ShootRequiresPendingHunter.validate(actor_id_changeset(hunter.id), [], %{})

      assert Keyword.fetch!(error, :field) == :actor_id
    end

    test "fails, on :actor_id, when the actor is not a player" do
      assert {:error, error} =
               ShootRequiresPendingHunter.validate(actor_id_changeset(UUID.generate()), [], %{})

      assert Keyword.fetch!(error, :field) == :actor_id
    end
  end
end
