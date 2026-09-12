defmodule WerewolfAsh.Accounts.UserTest do
  @moduledoc """
  Direct unit tests for `User.name` and the `:set_name` action/policy, which
  is otherwise only exercised at the GraphQL layer (see
  `WerewolfAshWeb.Graphql.AuthTest`).
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias WerewolfAsh.Accounts
  alias WerewolfAsh.Accounts.User

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
end
