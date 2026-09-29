defmodule WerewolfAsh.Games.Player.Validations.OwnerCannotLeaveTest do
  @moduledoc """
  Direct unit tests for the owner-cannot-leave validation (rule 26,
  werewolf_ash-27w.3).
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.ActionInput
  alias Ash.Resource.Validation.Context
  alias WerewolfAsh.Games.Player
  alias WerewolfAsh.Games.Player.Validations.OwnerCannotLeave

  defp input(game_id) do
    ActionInput.for_action(Player, :leave_as_self, %{game_id: game_id})
  end

  describe "validate/3" do
    test "passes for a non-owner" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))
      non_owner = generate(user())

      assert OwnerCannotLeave.validate(input(game.id), [], %Context{actor: non_owner}) == :ok
    end

    test "fails on :game_id for the owner" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))

      assert {:error, error} =
               OwnerCannotLeave.validate(input(game.id), [], %Context{actor: owner})

      assert Keyword.fetch!(error, :field) == :game_id
    end

    test "accepts an Ash.ActionInput subject" do
      owner = generate(user())
      game = generate(game(owner_id: owner.id))

      assert %ActionInput{} = subject = input(game.id)
      assert {:error, _error} = OwnerCannotLeave.validate(subject, [], %Context{actor: owner})
    end
  end
end
