defmodule WerewolfAsh.Games.Game.Validations.ActorIsOwnerTest do
  use ExUnit.Case, async: true

  alias Ash.Changeset
  alias Ash.UUID
  alias WerewolfAsh.Games.Game
  alias WerewolfAsh.Games.Game.Validations.ActorIsOwner

  defp changeset(owner_id), do: Changeset.new(%Game{owner_id: owner_id})

  describe "validate/3" do
    test "passes when the actor's id matches the game's owner_id" do
      owner_id = UUID.generate()

      assert ActorIsOwner.validate(changeset(owner_id), [], %{actor: %{id: owner_id}}) == :ok
    end

    test "fails, on :owner_id, when there is no actor" do
      changeset = changeset(UUID.generate())

      assert {:error, error} = ActorIsOwner.validate(changeset, [], %{actor: nil})
      assert Keyword.fetch!(error, :field) == :owner_id
    end

    test "fails, on :owner_id, when the actor is a different user" do
      changeset = changeset(UUID.generate())

      assert {:error, error} =
               ActorIsOwner.validate(changeset, [], %{actor: %{id: UUID.generate()}})

      assert Keyword.fetch!(error, :field) == :owner_id
    end
  end
end
