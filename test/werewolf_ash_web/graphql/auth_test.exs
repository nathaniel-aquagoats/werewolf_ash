defmodule WerewolfAshWeb.Graphql.AuthTest do
  @moduledoc """
  Exercises the auth flow end to end through the GraphQL layer: the HTTP
  endpoint (parsers, router pipeline, bearer plug, AshGraphql) and the
  subscriptions socket.
  """

  use WerewolfAshWeb.ConnCase, async: false

  import ExUnit.CaptureIO
  # `connect/2,3` clash between the HTTP verb helper and the socket helper
  import Phoenix.ConnTest, except: [connect: 2, connect: 3]
  import Phoenix.ChannelTest, only: [connect: 2, connect: 3]

  @register """
  mutation Register($input: RegisterWithPasswordInput!) {
    registerWithPassword(input: $input) {
      result { id email }
      metadata { token }
      errors { message fields }
    }
  }
  """

  @sign_in """
  mutation SignIn($email: String!, $password: String!) {
    signInWithPassword(email: $email, password: $password) {
      id
      email
      token
    }
  }
  """

  @current_user """
  query { currentUser { id email } }
  """

  defp gql(conn, query, variables \\ %{}) do
    conn
    |> post("/gql", %{"query" => query, "variables" => variables})
    |> json_response(200)
  end

  defp unique_email, do: "player-#{System.unique_integer([:positive])}@example.com"

  # The confirmation add-on's dev sender prints the confirmation link on
  # registration; keep it out of the test output.
  defp register(conn, email, password) do
    {response, _io} =
      with_io(fn ->
        gql(conn, @register, %{
          "input" => %{
            "email" => email,
            "password" => password,
            "passwordConfirmation" => password
          }
        })
      end)

    response
  end

  test "register -> sign in -> authenticated currentUser", %{conn: conn} do
    email = unique_email()
    password = "correct horse battery staple"

    # 1. register returns the user and a token
    assert %{
             "data" => %{
               "registerWithPassword" => %{
                 "result" => %{"id" => id, "email" => ^email},
                 "metadata" => %{"token" => register_token},
                 "errors" => []
               }
             }
           } = register(conn, email, password)

    assert is_binary(register_token)

    # 2. sign in with the same credentials returns a (fresh) token
    assert %{
             "data" => %{
               "signInWithPassword" => %{"id" => ^id, "email" => ^email, "token" => token}
             }
           } = gql(conn, @sign_in, %{"email" => email, "password" => password})

    assert is_binary(token)

    # 3. the bearer token identifies the actor for currentUser
    assert %{"data" => %{"currentUser" => %{"id" => ^id, "email" => ^email}}} =
             conn
             |> put_req_header("authorization", "Bearer #{token}")
             |> gql(@current_user)

    # the registration token is a valid bearer token too
    assert %{"data" => %{"currentUser" => %{"id" => ^id}}} =
             conn
             |> put_req_header("authorization", "Bearer #{register_token}")
             |> gql(@current_user)
  end

  test "currentUser is null (and not an error) without a valid bearer token", %{conn: conn} do
    anonymous = %{"data" => %{"currentUser" => nil}}

    assert gql(conn, @current_user) == anonymous

    assert conn
           |> put_req_header("authorization", "Bearer not.a.token")
           |> gql(@current_user) == anonymous
  end

  test "sign in with a wrong password fails and issues no token", %{conn: conn} do
    email = unique_email()
    register(conn, email, "correct horse battery staple")

    assert %{"data" => nil, "errors" => [%{"code" => "authentication_failed"}]} =
             gql(conn, @sign_in, %{"email" => email, "password" => "wrong password"})
  end

  test "the GraphQL socket sets the actor from a bearer token", %{conn: conn} do
    email = unique_email()
    password = "correct horse battery staple"

    %{
      "data" => %{
        "registerWithPassword" => %{"result" => %{"id" => id}, "metadata" => %{"token" => token}}
      }
    } =
      register(conn, email, password)

    # via the channels client's `authToken` (Sec-WebSocket-Protocol / Authorization header)
    assert {:ok, socket} =
             connect(WerewolfAshWeb.GraphqlSocket, %{}, connect_info: %{auth_token: token})

    assert %{actor: %WerewolfAsh.Accounts.User{id: ^id}} = socket.assigns.absinthe.opts[:context]

    # a token in the connect params is deliberately ignored (query-string credential)
    assert {:ok, socket} = connect(WerewolfAshWeb.GraphqlSocket, %{"token" => token})
    assert %{actor: nil} = socket.assigns.absinthe.opts[:context]

    # invalid token and no token both connect anonymously
    assert {:ok, socket} =
             connect(WerewolfAshWeb.GraphqlSocket, %{}, connect_info: %{auth_token: "garbage"})

    assert %{actor: nil} = socket.assigns.absinthe.opts[:context]

    assert {:ok, socket} = connect(WerewolfAshWeb.GraphqlSocket, %{})
    assert %{actor: nil} = socket.assigns.absinthe.opts[:context]
  end
end
