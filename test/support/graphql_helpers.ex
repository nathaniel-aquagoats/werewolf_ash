defmodule WerewolfAsh.GraphqlHelpers do
  @moduledoc """
  GraphQL test helpers for werewolf_ash-27w.3: requests a magic link for a
  seeded, named user and signs them in over `/gql`, returning a conn
  carrying their bearer token - modelled on
  `WerewolfAshWeb.Graphql.AuthTest`'s own `request_token`/`sign_in`, kept
  separate from that file per the bead's own instruction. Games and seats
  are staged directly through the domain (`WerewolfAsh.Generators`); only
  sign-in itself goes through GraphQL.

  A caller must first call `capture_magic_links!/0` from its own `setup`
  block (the sender forwards the token to `Application.get_env(:werewolf_ash,
  :magic_link_test_pid)`, a single global setting) and run `async: false`.
  """

  import ExUnit.Assertions
  import ExUnit.CaptureIO
  import Phoenix.ConnTest

  alias ExUnit.Callbacks
  alias Plug.Conn

  @endpoint WerewolfAshWeb.Endpoint

  @request_magic_link """
  mutation RequestMagicLink($email: String!) {
    requestMagicLink(email: $email)
  }
  """

  @sign_in """
  mutation SignIn($token: String!) {
    signInWithMagicLink(token: $token) {
      metadata { token }
      errors { message fields code }
    }
  }
  """

  @doc """
  Registers the calling test process to receive the magic-link token the
  sender would otherwise only log, and cleans up on exit. Call from a
  `setup do ... end` block in a `ConnCase`, `async: false`.
  """
  def capture_magic_links! do
    Application.put_env(:werewolf_ash, :magic_link_test_pid, self())

    Callbacks.on_exit(fn ->
      Application.delete_env(:werewolf_ash, :magic_link_test_pid)
    end)
  end

  @doc "Posts a GraphQL query/mutation to `/gql` and returns the decoded JSON response."
  def gql(conn, query, variables \\ %{}) do
    conn
    |> post("/gql", %{"query" => query, "variables" => variables})
    |> json_response(200)
  end

  @doc "Requests a magic link for `email` and returns the token captured by `capture_magic_links!/0`."
  def request_token(conn, email) do
    {response, _io} = with_io(fn -> gql(conn, @request_magic_link, %{"email" => email}) end)
    assert %{"data" => %{"requestMagicLink" => true}} = response
    assert_received {:magic_link_token, ^email, token}
    token
  end

  @doc """
  Signs the given seeded `WerewolfAsh.Accounts.User` in over GraphQL (by
  their own email, unchanged by `sign_in_with_magic_link`'s own
  `upsert_fields [:email]`) and returns a conn carrying their bearer token.
  """
  def sign_in_as(conn, %{email: email}) do
    email = to_string(email)
    token = request_token(conn, email)

    assert %{"data" => %{"signInWithMagicLink" => %{"metadata" => %{"token" => bearer}}}} =
             gql(conn, @sign_in, %{"token" => token})

    Conn.put_req_header(conn, "authorization", "Bearer #{bearer}")
  end
end
