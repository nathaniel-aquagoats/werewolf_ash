defmodule WerewolfAsh.Games.Player.Validations.GameNotFullTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias Ash.UUID
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Player
  alias WerewolfAsh.Games.Player.Validations.GameNotFull

  describe "init/1" do
    test "accepts an atom field" do
      assert GameNotFull.init(field: :game_id) == {:ok, [field: :game_id]}
    end

    test "rejects anything that is not an atom, or nil" do
      assert {:error, _reason} = GameNotFull.init(field: "game_id")
      assert {:error, _reason} = GameNotFull.init(field: nil)
    end
  end

  describe "validate/3" do
    test "passes below max_players" do
      game =
        generate(game())
        |> update_max_players(2)

      changeset = create_changeset(game)

      assert GameNotFull.validate(changeset, [field: :game_id], %{}) == :ok
    end

    test "fails, on the field its options say to, once max_players is already seated" do
      game =
        generate(game())
        |> update_max_players(1)

      changeset = create_changeset(game)

      assert {:error, error} = GameNotFull.validate(changeset, [field: :join_code], %{})
      assert Keyword.fetch!(error, :field) == :join_code
    end

    test "never fires when max_players is nil" do
      game = generate(game())
      changeset = create_changeset(game)

      assert GameNotFull.validate(changeset, [field: :game_id], %{}) == :ok
    end

    test "fails, on the field its options say to, when game_id names no row" do
      changeset = create_changeset(%{id: UUID.generate()})

      assert {:error, error} = GameNotFull.validate(changeset, [field: :game_id], %{})
      assert Keyword.fetch!(error, :field) == :game_id
    end
  end

  # Disables every special so the composition-fits check (rule 7) tolerates a
  # small max_players: with no specials, only the werewolf floor of 1 is
  # required, which fits any max_players >= 1.
  defp update_max_players(game, max_players) do
    Games.update_game_settings!(
      game,
      %{
        max_players: max_players,
        min_players: 1,
        seer_enabled: false,
        bodyguard_enabled: false,
        hunter_enabled: false
      },
      actor: %{id: game.owner_id}
    )
  end

  defp create_changeset(game) do
    user = generate(user())

    Changeset.for_create(Player, :create, %{game_id: game.id, user_id: user.id},
      authorize?: false
    )
  end
end
