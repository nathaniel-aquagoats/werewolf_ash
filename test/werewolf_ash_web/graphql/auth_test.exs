defmodule WerewolfAshWeb.Graphql.AuthTest do
  @moduledoc """
  Exercises the magic-link auth flow end to end through the GraphQL layer
  (the HTTP endpoint and the subscriptions socket), plus direct unit tests
  for the small pieces of our own code that flow relies on.
  """

  use WerewolfAshWeb.ConnCase, async: false

  import ExUnit.CaptureIO
  import Swoosh.TestAssertions
  # `connect/2,3` clash between the HTTP verb helper and the socket helper
  import Phoenix.ConnTest, except: [connect: 2, connect: 3]
  import Phoenix.ChannelTest, only: [connect: 2, connect: 3]

  alias AshAuthentication.TokenResource
  alias Ecto.Changeset
  alias WerewolfAsh.Accounts.BearerToken
  alias WerewolfAsh.Accounts.Token
  alias WerewolfAsh.Accounts.User
  alias WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmail
  alias WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmailWorker
  alias WerewolfAsh.Repo

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

  @current_user_name """
  query { currentUser { name } }
  """

  @set_name """
  mutation SetName($name: String!) {
    setName(name: $name) {
      result { name }
      errors { message fields code }
    }
  }
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

  # Signs a fresh, nameless user in and returns a conn carrying its bearer
  # token, ready for authenticated requests.
  defp sign_in(conn) do
    token = request_token(conn, unique_email())

    assert %{"data" => %{"signInWithMagicLink" => %{"metadata" => %{"token" => bearer}}}} =
             gql(conn, @sign_in, %{"token" => token})

    put_req_header(conn, "authorization", "Bearer #{bearer}")
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

  describe "setName / currentUser.name" do
    test "currentUser.name is null before a name is set", %{conn: conn} do
      conn = sign_in(conn)

      assert %{"data" => %{"currentUser" => %{"name" => nil}}} = gql(conn, @current_user_name)
    end

    test "setName sets the signed-in user's own name, reflected by a follow-up currentUser",
         %{conn: conn} do
      conn = sign_in(conn)

      assert %{
               "data" => %{
                 "setName" => %{"result" => %{"name" => "Alice"}, "errors" => []}
               }
             } = gql(conn, @set_name, %{"name" => "Alice"})

      assert %{"data" => %{"currentUser" => %{"name" => "Alice"}}} =
               gql(conn, @current_user_name)
    end

    test "a blank name comes back as an entry in errors, not a crash", %{conn: conn} do
      conn = sign_in(conn)

      assert %{"data" => %{"setName" => %{"result" => nil, "errors" => [error]}}} =
               gql(conn, @set_name, %{"name" => "   "})

      assert error["fields"] == ["name"]
    end

    test "a call with no bearer token changes no User and comes back as an error, not a crash",
         %{conn: conn} do
      assert %{"data" => %{"setName" => %{"result" => nil, "errors" => [_error]}}} =
               gql(conn, @set_name, %{"name" => "Anyone"})
    end
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

    test "delivers the email to the resolved recipient with the deep link, not the removed web path" do
      capture_io(fn -> SendMagicLinkEmail.send("deliver@example.com", "deliver-token", []) end)

      assert :ok =
               perform_job(SendMagicLinkEmailWorker, %{
                 "email" => "deliver@example.com",
                 "token" => "deliver-token"
               })

      assert_email_sent(fn email ->
        email.to == [{"", "deliver@example.com"}] and
          String.contains?(email.text_body, "deliver-token") and
          not String.contains?(email.text_body, "/auth/user/magic_link")
      end)
    end

    test "the deep-link base URL is read at call time and can be overridden without recompiling" do
      original = Application.fetch_env!(:werewolf_ash, :magic_link_deep_link_base_url)
      Application.put_env(:werewolf_ash, :magic_link_deep_link_base_url, "sentinel://base")

      on_exit(fn ->
        Application.put_env(:werewolf_ash, :magic_link_deep_link_base_url, original)
      end)

      capture_io(fn -> SendMagicLinkEmail.send("override@example.com", "override-token", []) end)

      assert :ok =
               perform_job(SendMagicLinkEmailWorker, %{
                 "email" => "override@example.com",
                 "token" => "override-token"
               })

      assert_email_sent(fn email ->
        String.contains?(email.text_body, "sentinel://base?token=override-token")
      end)
    end

    test "the from address is read at call time and can be overridden without recompiling" do
      original = Application.fetch_env!(:werewolf_ash, :magic_link_from_address)
      Application.put_env(:werewolf_ash, :magic_link_from_address, "sentinel@example.com")

      on_exit(fn ->
        Application.put_env(:werewolf_ash, :magic_link_from_address, original)
      end)

      capture_io(fn -> SendMagicLinkEmail.send("from-test@example.com", "from-token", []) end)

      assert :ok =
               perform_job(SendMagicLinkEmailWorker, %{
                 "email" => "from-test@example.com",
                 "token" => "from-token"
               })

      assert_email_sent(fn email -> email.from == {"", "sentinel@example.com"} end)
    end

    test "still logs the token and deep link to the console, not the removed web path" do
      output =
        capture_io(fn -> SendMagicLinkEmail.send("console@example.com", "console-token", []) end)

      assert output =~ "console-token"
      assert output =~ SendMagicLinkEmail.magic_link_url("console-token")
      refute output =~ "/auth/user/magic_link"
    end

    test "enqueues exactly one job on the emails queue, carrying the address, token, and dedupe key (rules 2, 3, 6, 11)" do
      capture_io(fn -> SendMagicLinkEmail.send("queued@example.com", "queued-token", []) end)

      assert [%Oban.Job{queue: "emails", args: args}] =
               all_enqueued(
                 worker: SendMagicLinkEmailWorker,
                 args: %{"email" => "queued@example.com"}
               )

      assert args == %{
               "email" => "queued@example.com",
               "token" => "queued-token",
               "dedupe_key" => "queued@example.com"
             }
    end

    test "a second call for the same still-unfinished address enqueues no second job, even long after the first (rule 6)" do
      email = "dedupe@example.com"
      capture_io(fn -> SendMagicLinkEmail.send(email, "first-token", []) end)

      [job] = all_enqueued(worker: SendMagicLinkEmailWorker, args: %{"dedupe_key" => email})

      long_ago = DateTime.add(DateTime.utc_now(), -120, :second)
      job |> Changeset.change(inserted_at: long_ago) |> Repo.update!()

      capture_io(fn -> SendMagicLinkEmail.send(email, "second-token", []) end)

      assert [%{args: %{"token" => "first-token"}}] =
               all_enqueued(worker: SendMagicLinkEmailWorker, args: %{"dedupe_key" => email})
    end

    test "requests for differently-cased addresses collide on the same lowercased dedupe key (rule 6)" do
      capture_io(fn -> SendMagicLinkEmail.send("Foo@Example.com", "mixed-case-token", []) end)
      capture_io(fn -> SendMagicLinkEmail.send("foo@example.com", "lower-case-token", []) end)

      assert [%{args: %{"token" => "mixed-case-token"}}] =
               all_enqueued(
                 worker: SendMagicLinkEmailWorker,
                 args: %{"dedupe_key" => "foo@example.com"}
               )
    end

    test "once the earlier job has actually finished, a further call enqueues a fresh one (rule 7)" do
      email = "finished@example.com"
      capture_io(fn -> SendMagicLinkEmail.send(email, "first-token", []) end)

      # `all_enqueued/1` only reports unfinished jobs (available, scheduled,
      # suspended), so once the first job has actually finished it no longer
      # blocks - or shows up alongside - a fresh one.
      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :emails)
      assert [] = all_enqueued(worker: SendMagicLinkEmailWorker, args: %{"dedupe_key" => email})

      capture_io(fn -> SendMagicLinkEmail.send(email, "second-token", []) end)

      assert [%{args: %{"token" => "second-token"}}] =
               all_enqueued(worker: SendMagicLinkEmailWorker, args: %{"dedupe_key" => email})
    end
  end

  describe "SendMagicLinkEmail.magic_link_url/1 (unit)" do
    test "appends the token as a query parameter to the configured base URL" do
      base_url = Application.fetch_env!(:werewolf_ash, :magic_link_deep_link_base_url)

      assert SendMagicLinkEmail.magic_link_url("a-token") == "#{base_url}?token=a-token"
    end

    test "reads the base URL at call time, so it reflects an override" do
      original = Application.fetch_env!(:werewolf_ash, :magic_link_deep_link_base_url)
      Application.put_env(:werewolf_ash, :magic_link_deep_link_base_url, "sentinel://other")

      on_exit(fn ->
        Application.put_env(:werewolf_ash, :magic_link_deep_link_base_url, original)
      end)

      assert SendMagicLinkEmail.magic_link_url("a-token") == "sentinel://other?token=a-token"
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

    test "a revoked bearer token stops resolving, for user_from_token/1 and currentUser alike (rule 14)",
         %{conn: conn} do
      email = unique_email()
      token = request_token(conn, email)

      assert %{"data" => %{"signInWithMagicLink" => %{"metadata" => %{"token" => bearer}}}} =
               gql(conn, @sign_in, %{"token" => token})

      assert {:ok, %User{}} = BearerToken.user_from_token(bearer)

      assert :ok = TokenResource.revoke(Token, bearer)

      assert :error = BearerToken.user_from_token(bearer)

      assert conn
             |> put_req_header("authorization", "Bearer #{bearer}")
             |> gql(@current_user) == %{"data" => %{"currentUser" => nil}}
    end
  end
end
