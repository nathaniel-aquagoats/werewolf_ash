defmodule WerewolfAsh.Games.Action.Changes.RecordInvestigationResultTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Action.Changes.RecordInvestigationResult

  describe "change/3" do
    test "given an :investigate changeset targeting a werewolf, stages the true result" do
      game = generate(game())
      target = generate(player(game_id: game.id, role: :werewolf))

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:type, :investigate)
        |> Changeset.change_attribute(:target_id, target.id)

      changeset = RecordInvestigationResult.change(changeset, [], %{})

      assert Changeset.get_attribute(changeset, :result) == %{"is_werewolf" => true}
    end

    test "given an :investigate changeset targeting a non-werewolf, stages the false result" do
      game = generate(game())
      target = generate(player(game_id: game.id, role: :villager))

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:type, :investigate)
        |> Changeset.change_attribute(:target_id, target.id)

      changeset = RecordInvestigationResult.change(changeset, [], %{})

      assert Changeset.get_attribute(changeset, :result) == %{"is_werewolf" => false}
    end

    test "given any other type, does not touch result" do
      game = generate(game())
      target = generate(player(game_id: game.id, role: :werewolf))

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:type, :vote)
        |> Changeset.change_attribute(:target_id, target.id)

      assert RecordInvestigationResult.change(changeset, [], %{}) == changeset
    end
  end
end
