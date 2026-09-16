defmodule WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmailWorkerTest.FailingMailerAdapter do
  @moduledoc """
  A `Swoosh.Adapter` that always fails delivery, for exercising the worker's
  mailer-failure path (Rule 5) without a real provider.
  """

  use Swoosh.Adapter

  def deliver(_email, _config), do: {:error, :boom}
end

defmodule WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmailWorkerTest do
  @moduledoc """
  Direct unit tests for `SendMagicLinkEmailWorker.perform/1` — the background
  job `SendMagicLinkEmail.send/3` enqueues (see `WerewolfAshWeb.Graphql.AuthTest`
  for the enqueue/dedupe behaviour, and `WerewolfAsh.Accounts.UserTest` for the
  `request_magic_link` action itself).
  """

  use WerewolfAsh.DataCase, async: false

  import Swoosh.TestAssertions

  alias AshAuthentication.Jwt
  alias WerewolfAsh.Accounts.User
  alias WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmailWorker
  alias WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmailWorkerTest.FailingMailerAdapter

  defp valid_token(email) do
    {:ok, token, _claims} =
      Jwt.token_for_resource(
        User,
        %{"act" => :sign_in_with_magic_link, "identity" => email},
        [token_lifetime: {10, :minutes}, purpose: :magic_link],
        %{}
      )

    token
  end

  defp expired_token(email) do
    past = System.system_time(:second) - 60

    {:ok, token, _claims} =
      Jwt.token_for_resource(
        User,
        %{"act" => :sign_in_with_magic_link, "identity" => email, "exp" => past},
        [token_lifetime: {10, :minutes}, purpose: :magic_link],
        %{}
      )

    token
  end

  describe "perform/1" do
    test "delivers the email via WerewolfAsh.Mailer for a non-expired token (rule 4)" do
      email = "worker@example.com"
      token = valid_token(email)

      assert :ok =
               perform_job(SendMagicLinkEmailWorker, %{"email" => email, "token" => token})

      assert_email_sent(fn sent ->
        sent.to == [{"", email}] and String.contains?(sent.text_body, token)
      end)
    end

    test "surfaces a mailer failure as an error, so Oban counts and retries the attempt (rule 5)" do
      original = Application.fetch_env!(:werewolf_ash, WerewolfAsh.Mailer)
      Application.put_env(:werewolf_ash, WerewolfAsh.Mailer, adapter: FailingMailerAdapter)
      on_exit(fn -> Application.put_env(:werewolf_ash, WerewolfAsh.Mailer, original) end)

      email = "fail@example.com"
      token = valid_token(email)

      assert {:error, _reason} =
               perform_job(SendMagicLinkEmailWorker, %{"email" => email, "token" => token})
    end

    test "an already-expired token sends nothing, and is not a failure (rule 8)" do
      email = "expired@example.com"
      token = expired_token(email)

      assert :ok = perform_job(SendMagicLinkEmailWorker, %{"email" => email, "token" => token})

      refute_email_sent()
    end
  end

  describe "worker declaration (rules 3, 5)" do
    test "runs on its own :emails queue, distinct from :default" do
      assert SendMagicLinkEmailWorker.__opts__()[:queue] == :emails
    end

    test "gives up after 8 attempts" do
      assert SendMagicLinkEmailWorker.__opts__()[:max_attempts] == 8
    end
  end
end
