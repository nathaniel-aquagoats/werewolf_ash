defmodule WerewolfAsh.Games.Player.Validations.GameInLobbyTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games.Player.Validations.GameInLobby

  describe "init/1" do
    test "accepts an atom field" do
      assert GameInLobby.init(field: :game_id) == {:ok, [field: :game_id]}
    end

    test "rejects anything that is not an atom, or nil" do
      assert {:error, _reason} = GameInLobby.init(field: "game_id")
      assert {:error, _reason} = GameInLobby.init(field: nil)
    end
  end

  describe "validate/3" do
    test "passes when the referenced game is in :lobby" do
      game = generate(game())
      player = generate(player(game_id: game.id))

      changeset = Changeset.for_destroy(player, :destroy, %{}, authorize?: false)

      assert GameInLobby.validate(changeset, [field: :game_id], %{}) == :ok
    end

    test "fails, on the field its options say to, once the game has left the lobby" do
      game = generate(game())
      player = generate(player(game_id: game.id))

      game
      |> Changeset.for_update(:update, %{})
      |> Changeset.force_change_attribute(:state, :day)
      |> Ash.update!()

      changeset = Changeset.for_destroy(player, :destroy, %{}, authorize?: false)

      assert {:error, error} = GameInLobby.validate(changeset, [field: :join_code], %{})
      assert Keyword.fetch!(error, :field) == :join_code
    end
  end
end
