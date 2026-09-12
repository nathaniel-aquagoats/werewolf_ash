defmodule WerewolfAsh.Games.Player.Validations.UserHasNameTest do
  @moduledoc """
  Direct unit tests for the pure validation, plus its wiring into `Player`'s
  `:create`/`:join` actions is covered end to end in `GamesTest`.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games.Player
  alias WerewolfAsh.Games.Player.Validations.UserHasName

  defp changeset_for(user_id) do
    Player
    |> Changeset.new()
    |> Changeset.change_attribute(:user_id, user_id)
  end

  test "ok for a user with a name" do
    user = generate(user(name: "Alice"))

    assert UserHasName.validate(changeset_for(user.id), [], %{}) == :ok
  end

  test "errors on :name for a user with no name" do
    user = generate(user(name: nil))

    assert {:error, error} = UserHasName.validate(changeset_for(user.id), [], %{})
    assert Keyword.fetch!(error, :field) == :name
  end

  test "ok (defers to the action's own required-input check) when user_id is absent" do
    assert UserHasName.validate(changeset_for(nil), [], %{}) == :ok
  end
end
