defmodule WerewolfAshWeb.Graphql.AuthTest do
  @moduledoc """
  Exercises the magic-link auth flow end to end through the GraphQL layer
  (the HTTP endpoint and the subscriptions socket), plus direct unit tests
  for the small pieces of our own code that flow relies on.
  """

  use WerewolfAshWeb.ConnCase, async: false

  import ExUnit.CaptureIO
  # `connect/2,3` clash between the HTTP verb helper and the socket helper
  import Phoenix.ConnTest, except: [connect: 2, connect: 3]
  import Phoenix.ChannelTest, only: [connect: 2, connect: 3]

  alias WerewolfAsh.Accounts.BearerToken
  alias WerewolfAsh.Accounts.User
  alias WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmail

  @request_magic_link """
  mutation RequestMagicLink($email: String!) {
    requestMagicLink(email: $email)
  }
  """

  @sign_in """
  mutation SignIn($token: String!) {
    signInWithMagicLink(token: $token) {
      result { id email }
      metadata { token }
      errors { message fields code }
    }
  }
  """

  @current_user """
  query { currentUser { id email } }
  """

  setup do
    Application.put_env(:werewolf_ash, :magic_link_test_pid, self())
    on_exit(fn -> Application.delete_env(:werewolf_ash, :magic_link_test_pid) end)
    :ok
  end

  defp gql(conn, query, variables \\ %{}) do
    conn
    |> post("/gql", %{"query" => query, "variables" => variables})
    |> json_response(200)
  end

  defp unique_email, do: "player-#{System.unique_integer([:positive])}@example.com"

  # Requests a magic link and captures the token the sender forwards to this
  # test process (see `SendMagicLinkEmail`), keeping the sender's dev log out
  # of test output.
  defp request_token(conn, email) do
    {response, _io} = with_io(fn -> gql(conn, @request_magic_link, %{"email" => email}) end)
    assert %{"data" => %{"requestMagicLink" => true}} = response
    assert_received {:magic_link_token, ^email, token}
    token
  end

  describe "magic-link sign-in flow" do
    test "request -> sign in -> authenticated currentUser, registering a new user on first use",
         %{conn: conn} do
      email = unique_email()
      token = request_token(conn, email)

      assert %{
               "data" => %{
                 "signInWithMagicLink" => %{
                   "result" => %{"id" => id, "email" => ^email},
                   "metadata" => %{"token" => bearer},
                   "errors" => []
                 }
               }
             } = gql(conn, @sign_in, %{"token" => token})

      assert is_binary(bearer)

      assert %{"data" => %{"currentUser" => %{"id" => ^id, "email" => ^email}}} =
               conn
               |> put_req_header("authorization", "Bearer #{bearer}")
               |> gql(@current_user)
    end

    test "a magic-link token can only be used once", %{conn: conn} do
      email = unique_email()
      token = request_token(conn, email)

      assert %{"data" => %{"signInWithMagicLink" => %{"errors" => []}}} =
               gql(conn, @sign_in, %{"token" => token})

      assert %{
               "data" => %{
                 "signInWithMagicLink" => %{
                   "result" => nil,
                   "errors" => [%{"code" => "invalid_token"}]
                 }
               }
             } = gql(conn, @sign_in, %{"token" => token})
    end

    test "a garbage token is rejected with a generic invalid-token error", %{conn: conn} do
      assert %{
               "data" => %{
                 "signInWithMagicLink" => %{
                   "result" => nil,
                   "errors" => [%{"code" => "invalid_token"}]
                 }
               }
             } = gql(conn, @sign_in, %{"token" => "not.a.real.token"})
    end

    test "requestMagicLink succeeds identically for an unregistered email as for a registered one",
         %{conn: conn} do
      registered_email = unique_email()
      token = request_token(conn, registered_email)

      assert %{"data" => %{"signInWithMagicLink" => %{"errors" => []}}} =
               gql(conn, @sign_in, %{"token" => token})

      unknown_email = unique_email()

      {known_response, _io} =
        with_io(fn -> gql(conn, @request_magic_link, %{"email" => registered_email}) end)

      {unknown_response, _io} =
        with_io(fn -> gql(conn, @request_magic_link, %{"email" => unknown_email}) end)

      assert known_response == unknown_response
    end
  end

  test "currentUser is null (and not an error) without a valid bearer token", %{conn: conn} do
    anonymous = %{"data" => %{"currentUser" => nil}}

    assert gql(conn, @current_user) == anonymous

    assert conn
           |> put_req_header("authorization", "Bearer not.a.token")
           |> gql(@current_user) == anonymous
  end

  test "the GraphQL socket sets the actor from a bearer token", %{conn: conn} do
    email = unique_email()
    token = request_token(conn, email)

    assert %{
             "data" => %{
               "signInWithMagicLink" => %{
                 "result" => %{"id" => id},
                 "metadata" => %{"token" => bearer}
               }
             }
           } = gql(conn, @sign_in, %{"token" => token})

    # via the channels client's `authToken` (Sec-WebSocket-Protocol / Authorization header)
    assert {:ok, socket} =
             connect(WerewolfAshWeb.GraphqlSocket, %{}, connect_info: %{auth_token: bearer})

    assert %{actor: %User{id: ^id}} = socket.assigns.absinthe.opts[:context]

    # a token in the connect params is deliberately ignored (query-string credential)
    assert {:ok, socket} = connect(WerewolfAshWeb.GraphqlSocket, %{"token" => bearer})
    assert %{actor: nil} = socket.assigns.absinthe.opts[:context]

    # invalid token and no token both connect anonymously
    assert {:ok, socket} =
             connect(WerewolfAshWeb.GraphqlSocket, %{}, connect_info: %{auth_token: "garbage"})

    assert %{actor: nil} = socket.assigns.absinthe.opts[:context]

    assert {:ok, socket} = connect(WerewolfAshWeb.GraphqlSocket, %{})
    assert %{actor: nil} = socket.assigns.absinthe.opts[:context]
  end

  describe "SendMagicLinkEmail (unit)" do
    test "forwards the token to the configured test pid, for an existing user" do
      user = %User{email: "known@example.com"}

      capture_io(fn -> SendMagicLinkEmail.send(user, "a-token", []) end)

      assert_received {:magic_link_token, "known@example.com", "a-token"}
    end

    test "forwards the token to the configured test pid, for an email with no user yet" do
      capture_io(fn -> SendMagicLinkEmail.send("new@example.com", "another-token", []) end)

      assert_received {:magic_link_token, "new@example.com", "another-token"}
    end
  end

  describe "BearerToken.user_from_token/1 (unit)" do
    test "resolves a valid bearer token to the user it was issued for", %{conn: conn} do
      email = unique_email()
      token = request_token(conn, email)

      assert %{"data" => %{"signInWithMagicLink" => %{"result" => %{"id" => id}} = payload}} =
               gql(conn, @sign_in, %{"token" => token})

      bearer = payload["metadata"]["token"]

      assert {:ok, %User{id: ^id}} = BearerToken.user_from_token(bearer)
    end

    test "returns :error for a token that isn't a valid, currently-issued user token" do
      assert :error = BearerToken.user_from_token("garbage")
    end
  end
end
