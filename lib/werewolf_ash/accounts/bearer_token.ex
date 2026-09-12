defmodule WerewolfAsh.Accounts.BearerToken do
  @moduledoc """
  Resolves an AshAuthentication bearer token (as issued by
  `requestMagicLink` / `signInWithMagicLink`) to the `User` it belongs to.

  Used by the GraphQL socket, where there is no `Plug.Conn` for
  `AshAuthentication.Plug.Helpers.retrieve_from_bearer/3` (which the HTTP
  pipeline uses). Mirrors the checks that helper performs:

    * signature and standard claims are verified by `AshAuthentication.Jwt.verify/2`
    * purpose-scoped tokens (sign-in, reset, ...) and delegated (`act`) tokens
      are rejected
    * the token must still be present in the token resource when
      `require_token_presence_for_authentication?` is set (log-out-everywhere)
    * the `sub` claim is exchanged for a user via `AshAuthentication.subject_to_user/2`
  """

  alias AshAuthentication.Info
  alias AshAuthentication.Jwt
  alias AshAuthentication.TokenResource.Actions

  @otp_app :werewolf_ash

  @doc """
  Resolves a raw JWT (no `Bearer ` prefix) to a user.

  Returns `:error` for anything that is not a currently valid user token.
  """
  @spec user_from_token(String.t() | nil) :: {:ok, Ash.Resource.record()} | :error
  def user_from_token(token) when is_binary(token) do
    with {:ok, %{"sub" => subject, "jti" => jti} = claims, resource}
         when not is_map_key(claims, "act") <- Jwt.verify(token, @otp_app),
         true <- usable_as_bearer_token?(claims),
         :ok <- ensure_token_present(resource, jti),
         {:ok, user} <- AshAuthentication.subject_to_user(subject, resource) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  def user_from_token(_), do: :error

  defp usable_as_bearer_token?(claims) do
    case Map.get(claims, "purpose") do
      nil -> true
      "user" -> true
      _ -> false
    end
  end

  defp ensure_token_present(resource, jti) do
    if Info.authentication_tokens_require_token_presence_for_authentication?(resource) do
      with {:ok, token_resource} <- Info.authentication_tokens_token_resource(resource),
           {:ok, [_token_record]} <-
             Actions.get_token(token_resource, %{"jti" => jti, "purpose" => "user"}) do
        :ok
      else
        _ -> :error
      end
    else
      :ok
    end
  end
end
