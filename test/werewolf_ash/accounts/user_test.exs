defmodule WerewolfAsh.Accounts.UserTest do
  @moduledoc """
  Direct unit tests for `User.name` and the `:set_name` action/policy, which
  is otherwise only exercised at the GraphQL layer (see
  `WerewolfAshWeb.Graphql.AuthTest`).
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Query
  alias WerewolfAsh.Accounts
  alias WerewolfAsh.Accounts.User
  alias WerewolfAsh.Games

  describe "set_name/2,3 (the attribute and action)" do
    test "trims and stores a valid name" do
      user = generate(user(name: nil))

      updated = Accounts.set_name!(user, "  Alice  ", actor: user)

      assert updated.name == "Alice"
    end

    test "a blank or whitespace-only name is rejected as a missing required attribute" do
      user = generate(user(name: nil))

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Accounts.set_name(user, "   ", actor: user)

      assert %Ash.Error.Changes.Required{field: :name} = error
      assert is_nil(Ash.get!(User, user.id, authorize?: false).name)
    end

    test "a name over 40 characters is rejected" do
      user = generate(user(name: nil))
      too_long = String.duplicate("a", 41)

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Accounts.set_name(user, too_long, actor: user)

      assert %Ash.Error.Changes.InvalidAttribute{field: :name} = error
    end
  end

  describe "set_name/2,3 (policy)" do
    test "the record's own user may set their own name" do
      user = generate(user(name: nil))

      assert %{name: "Bob"} = Accounts.set_name!(user, "Bob", actor: user)
    end

    test "a different actor is forbidden and the name is unchanged" do
      user = generate(user(name: "Original"))
      other = generate(user())

      assert {:error, %Ash.Error.Forbidden{}} = Accounts.set_name(user, "Hijacked", actor: other)
      assert Ash.get!(User, user.id, authorize?: false).name == "Original"
    end

    test "no actor (anonymous) is forbidden and the name is unchanged" do
      user = generate(user(name: "Original"))

      assert {:error, %Ash.Error.Forbidden{}} = Accounts.set_name(user, "Anon", actor: nil)
      assert Ash.get!(User, user.id, authorize?: false).name == "Original"
    end
  end

  describe "the bare :read action (rule 13)" do
    test "returns nothing for an anonymous actor" do
      user = generate(user())

      assert Ash.read!(User) == []
      assert {:error, %Ash.Error.Invalid{}} = Ash.get(User, user.id)
    end

    test "returns nothing for a signed-in actor who shares no game with the target" do
      target = generate(user())
      stranger = generate(user())

      assert Ash.read!(User, actor: stranger) == []
      assert {:error, %Ash.Error.Invalid{}} = Ash.get(User, target.id, actor: stranger)
    end
  end

  describe "rule 17 - the shared-game read grant" do
    test "a fellow player of the same game can read the target's :id and :name" do
      game = generate(game())
      alice = generate(user(name: "Alice"))
      bob = generate(user(name: "Bob"))
      Games.add_player!(game.id, alice.id)
      Games.add_player!(game.id, bob.id)

      reloaded = Ash.get!(User, bob.id, actor: alice)
      assert reloaded.id == bob.id
      assert reloaded.name == "Bob"
    end

    test "a signed-in user sharing no game with the target gets nothing" do
      game = generate(game())
      alice = generate(user())
      Games.add_player!(game.id, alice.id)
      stranger = generate(user())

      assert {:error, %Ash.Error.Invalid{}} = Ash.get(User, alice.id, actor: stranger)
    end

    test "email stays visible only on the actor's own row, even for a fellow player" do
      game = generate(game())
      alice = generate(user())
      bob = generate(user())
      Games.add_player!(game.id, alice.id)
      Games.add_player!(game.id, bob.id)

      reloaded = Ash.get!(User, bob.id, actor: alice)
      assert %Ash.ForbiddenField{} = reloaded.email

      own_row = Ash.get!(User, alice.id, actor: alice)
      assert own_row.email == alice.email
    end

    test "a signed-in actor seated in no game at all still reads their own :name via :current_user" do
      user = generate(user(name: "Solo"))

      reloaded =
        User
        |> Query.for_read(:current_user, %{}, actor: user)
        |> Ash.read_one!()

      assert reloaded.id == user.id
      assert reloaded.name == "Solo"
    end

    test "a mismatched actor reads nothing via :current_user, even by id" do
      user = generate(user(name: "Solo"))
      stranger = generate(user())

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.get(User, user.id, action: :current_user, actor: stranger)

      assert Ash.get!(User, user.id, action: :current_user, actor: user).id == user.id
    end
  end
end
