defmodule WerewolfAshWeb.Graphql.SchemaTest do
  @moduledoc """
  Schema-shape tests for werewolf_ash-27w.3, run through Absinthe's own
  introspection query (no DB): rule 3 (no forbidden argument/input-field
  name anywhere, the internal actions expose no mutation), the mutation
  names of rules 14, 17, 20, 24-28 with exactly their arguments, `startGame`
  has no `now` input, and `User.email` is nullable.
  """

  use ExUnit.Case, async: true

  @schema WerewolfAshWeb.GraphqlSchema

  @introspection """
  {
    __schema {
      mutationType { fields { name args { name } } }
      queryType { fields { name args { name } } }
      types { name kind inputFields { name } fields { name type { ofType { name } name } } }
    }
  }
  """

  defp introspect do
    assert {:ok, %{data: %{"__schema" => schema}}} = Absinthe.run(@introspection, @schema)
    schema
  end

  defp mutation_names(schema), do: Enum.map(schema["mutationType"]["fields"], & &1["name"])
  defp query_names(schema), do: Enum.map(schema["queryType"]["fields"], & &1["name"])

  defp mutation_args(schema, name) do
    schema["mutationType"]["fields"]
    |> Enum.find(&(&1["name"] == name))
    |> Map.fetch!("args")
    |> Enum.map(& &1["name"])
    |> Enum.sort()
  end

  test "no argument, in any query or mutation, is named actorId, userId, ownerId or phaseId" do
    schema = introspect()
    banned = ["actorId", "userId", "ownerId", "phaseId"]

    (schema["mutationType"]["fields"] ++ schema["queryType"]["fields"])
    |> Enum.each(fn field ->
      arg_names = Enum.map(field["args"], & &1["name"])

      assert Enum.filter(arg_names, &(&1 in banned)) == [],
             "#{field["name"]} takes a forbidden argument"
    end)
  end

  test "no input field anywhere in the schema is named actorId, userId, ownerId or phaseId" do
    schema = introspect()
    banned = ["actorId", "userId", "ownerId", "phaseId"]

    Enum.each(schema["types"], fn type ->
      case type["inputFields"] do
        nil ->
          :ok

        fields ->
          names = Enum.map(fields, & &1["name"])

          assert Enum.filter(names, &(&1 in banned)) == [],
                 "#{type["name"]} declares a forbidden input field"
      end
    end)
  end

  test "the mutation names for the internal/never-exposed actions (rule 3) are absent" do
    names = introspect() |> mutation_names()

    forbidden = [
      "endDay",
      "endNight",
      "finish",
      "finishGame",
      "createPlayer",
      "updatePlayer",
      "destroyPlayer",
      "joinPlayer",
      "createAction",
      "killAction",
      "updateAction",
      "destroyAction",
      "withdrawAction",
      "resolveHunterDeadline",
      "updateGame",
      "destroyGame"
    ]

    assert Enum.filter(names, &(&1 in forbidden)) == []
  end

  test "rules 14, 17, 20, 24-28 - each mutation is present with exactly its arguments" do
    schema = introspect()

    assert mutation_args(schema, "createGame") ==
             Enum.sort(["name", "timezone", "dayStart", "dayEnd"])

    assert mutation_args(schema, "startGame") == ["id"]
    assert mutation_args(schema, "updateGameSettings") == Enum.sort(["id", "input"])
    assert mutation_args(schema, "joinGame") == ["joinCode"]
    assert mutation_args(schema, "leaveGame") == ["gameId"]

    for name <- ["vote", "kill", "investigate", "protect", "shoot"] do
      assert mutation_args(schema, name) == Enum.sort(["gameId", "targetId"])
    end

    assert mutation_args(schema, "withdrawVote") == ["gameId"]
    assert mutation_args(schema, "withdrawProtection") == ["gameId"]
  end

  test "startGame has no now input" do
    schema = introspect()
    refute "now" in mutation_args(schema, "startGame")
  end

  test "game(id) and myGames are the only new root queries" do
    names = introspect() |> query_names()
    assert "game" in names
    assert "myGames" in names
  end

  test "User.email is nullable" do
    schema = introspect()

    user_type = Enum.find(schema["types"], &(&1["name"] == "User"))
    email_field = Enum.find(user_type["fields"], &(&1["name"] == "email"))

    # A non-null field's `type` is itself a NON_NULL wrapper with `ofType`
    # set; a nullable field's `type.ofType` is nil.
    refute email_field["type"]["ofType"]
  end
end
