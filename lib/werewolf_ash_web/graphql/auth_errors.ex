# AshGraphql ships an `AshGraphql.Error` implementation for
# `AshAuthentication.Errors.InvalidToken` (the error the magic-link
# create-based sign-in action raises for an invalid/expired/reused token),
# but it only compiles when ash_authentication happens to be compiled before
# ash_graphql (it is not a declared dependency, so the order is not
# guaranteed). Without it a failed sign-in surfaces as an opaque "Something
# went wrong" error. Provide the same implementation here whenever
# ash_graphql's is absent.
unless AshGraphql.Error.impl_for(%AshAuthentication.Errors.InvalidToken{}) do
  defimpl AshGraphql.Error, for: AshAuthentication.Errors.InvalidToken do
    def to_error(_error) do
      %{
        message: "An invalid token was presented",
        short_message: "Invalid token",
        fields: [],
        code: "invalid_token",
        vars: %{}
      }
    end
  end
end
