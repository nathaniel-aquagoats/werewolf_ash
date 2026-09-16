defmodule WerewolfAsh.Games.Action.Validations.PhaseNotEndedTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.ActionInput
  alias Ash.Changeset
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Action.Validations.PhaseNotEnded

  describe "validate/3 against a Changeset" do
    test "passes when the named phase's ended_at is nil" do
      game = generate(game())
      phase = generate(phase(game_id: game.id))

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:phase_id, phase.id)

      assert PhaseNotEnded.validate(changeset, [], %{}) == :ok
    end

    test "fails, on :phase_id, when the named phase has already ended" do
      game = generate(game())
      phase = generate(phase(game_id: game.id))
      Games.update_phase!(phase, %{ended_at: DateTime.utc_now()})

      changeset =
        %Action{}
        |> Changeset.new()
        |> Changeset.change_attribute(:phase_id, phase.id)

      assert {:error, error} = PhaseNotEnded.validate(changeset, [], %{})
      assert Keyword.fetch!(error, :field) == :phase_id
    end
  end

  describe "validate/3 against an Ash.ActionInput" do
    # Built the same way `:withdraw` itself receives input - `for_action/3`,
    # not a bare `new/1` + `set_argument/3` (that combination silently drops
    # the argument, since `set_argument/3` only casts against a bound
    # action's own declared arguments) - mirroring `Changeset.new/1` +
    # `change_attribute/3`'s role for the Changeset-based tests above as
    # closely as the two APIs allow.
    test "passes when the named phase's ended_at is nil" do
      game = generate(game())
      phase = generate(phase(game_id: game.id))

      input = ActionInput.for_action(Action, :withdraw, %{phase_id: phase.id})

      assert PhaseNotEnded.validate(input, [], %{}) == :ok
    end

    test "fails, on :phase_id, when the named phase has already ended" do
      game = generate(game())
      phase = generate(phase(game_id: game.id))
      Games.update_phase!(phase, %{ended_at: DateTime.utc_now()})

      input = ActionInput.for_action(Action, :withdraw, %{phase_id: phase.id})

      assert {:error, error} = PhaseNotEnded.validate(input, [], %{})
      assert Keyword.fetch!(error, :field) == :phase_id
    end
  end
end
