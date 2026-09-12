defmodule WerewolfAsh.Games.Message.Validations.AuthorMayPostTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Message
  alias WerewolfAsh.Games.Message.Validations.AuthorMayPost
  alias WerewolfAsh.Games.Player

  # check/3 is the pure rule the module pulls out for direct testing; no
  # database needed, so plain structs stand in for real players.
  describe "check/3 (the pure rule)" do
    test "a living player may post in the village channel" do
      player = %Player{game_id: "game-1", alive: true, role: :villager}
      assert AuthorMayPost.check(player, "game-1", :village) == :ok
    end

    test "a living werewolf may post in the wolves channel" do
      player = %Player{game_id: "game-1", alive: true, role: :werewolf}
      assert AuthorMayPost.check(player, "game-1", :wolves) == :ok
    end

    test "a dead player may not post anywhere" do
      player = %Player{game_id: "game-1", alive: false, role: :villager}

      assert {:error, error} = AuthorMayPost.check(player, "game-1", :village)
      assert Keyword.fetch!(error, :field) == :author_id
    end

    test "a living non-wolf may not post in the wolves channel" do
      player = %Player{game_id: "game-1", alive: true, role: :villager}

      assert {:error, error} = AuthorMayPost.check(player, "game-1", :wolves)
      assert Keyword.fetch!(error, :field) == :channel
    end

    test "no author, or an author from another game, is rejected" do
      assert {:error, missing} = AuthorMayPost.check(nil, "game-1", :village)
      assert Keyword.fetch!(missing, :field) == :author_id

      elsewhere = %Player{game_id: "game-2", alive: true, role: :villager}
      assert {:error, wrong_game} = AuthorMayPost.check(elsewhere, "game-1", :village)
      assert Keyword.fetch!(wrong_game, :field) == :author_id
    end
  end

  # validate/3's own job, beyond check/3, is looking the author up and
  # short-circuiting when the changeset is incomplete — tested here on a
  # changeset built directly, without going through the `send_message` action
  # that message_test.exs already exercises end-to-end.
  describe "validate/3" do
    setup do
      %{game: generate(game())}
    end

    defp changeset_for(game_id, author_id, channel) do
      Message
      |> Changeset.new()
      |> Changeset.change_attribute(:game_id, game_id)
      |> Changeset.change_attribute(:author_id, author_id)
      |> Changeset.change_attribute(:channel, channel)
    end

    test "does nothing when a required attribute is missing", %{game: game} do
      changeset = changeset_for(game.id, nil, :village)
      assert AuthorMayPost.validate(changeset, [], %{}) == :ok
    end

    test "passes for a real, living, eligible author", %{game: game} do
      villager = generate(player(game_id: game.id, role: :villager))
      changeset = changeset_for(game.id, villager.id, :village)

      assert AuthorMayPost.validate(changeset, [], %{}) == :ok
    end

    test "fails for a real author the rule rejects", %{game: game} do
      dead =
        generate(player(game_id: game.id, role: :villager))
        |> Games.update_player!(%{alive: false})

      changeset = changeset_for(game.id, dead.id, :village)

      assert {:error, error} = AuthorMayPost.validate(changeset, [], %{})
      assert Keyword.fetch!(error, :field) == :author_id
    end
  end
end
