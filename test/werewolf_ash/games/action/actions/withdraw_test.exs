defmodule WerewolfAsh.Games.Action.Actions.WithdrawTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.ActionInput
  alias Ash.Resource.Actions.Implementation.Context
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Action.Actions.Withdraw

  defp input(phase, actor, type) do
    ActionInput.for_action(Action, :withdraw, %{
      phase_id: phase.id,
      actor_id: actor.id,
      type: type
    })
  end

  defp remaining(phase, actor, type) do
    Games.list_actions!(
      query: [filter: [phase_id: phase.id, actor_id: actor.id, type: type]],
      authorize?: false
    )
  end

  describe "run/3" do
    test "given a matching row, it is destroyed (rule 6)" do
      game = generate(game())
      phase = generate(phase(game_id: game.id, kind: :day))
      actor = generate(player(game_id: game.id))
      target = generate(player(game_id: game.id))

      Games.create_action!(phase.id, actor.id, target.id, :vote, authorize?: false)

      assert Withdraw.run(input(phase, actor, :vote), [], %Context{authorize?: false}) == :ok
      assert remaining(phase, actor, :vote) == []
    end

    test "given none, changes nothing and raises no error (rule 9)" do
      game = generate(game())
      phase = generate(phase(game_id: game.id, kind: :day))
      actor = generate(player(game_id: game.id))

      assert Withdraw.run(input(phase, actor, :protect), [], %Context{authorize?: false}) ==
               :ok

      assert remaining(phase, actor, :protect) == []
    end
  end
end
