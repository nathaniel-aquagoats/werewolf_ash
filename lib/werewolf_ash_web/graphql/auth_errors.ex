# AshGraphql ships an `AshGraphql.Error` implementation for
# `AshAuthentication.Errors.AuthenticationFailed`, but only compiles it when
# ash_authentication happens to be compiled before ash_graphql (it is not a
# declared dependency, so the order is not guaranteed). Without it a failed
# sign-in surfaces as an opaque "Something went wrong" error. Provide the same
# implementation here whenever ash_graphql's is absent.
unless AshGraphql.Error.impl_for(%AshAuthentication.Errors.AuthenticationFailed{}) do
  defimpl AshGraphql.Error, for: AshAuthentication.Errors.AuthenticationFailed do
    def to_error(_error) do
      %{
        message: "Authentication failed",
        short_message: "Authentication failed",
        fields: [],
        code: "authentication_failed",
        vars: %{}
      }
    end
  end
end
