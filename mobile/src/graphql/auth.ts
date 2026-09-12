import { graphql } from '../gql';

/**
 * The user identified by the request's bearer token, if any.
 * Mirrors `WerewolfAsh.Accounts` `current_user` query.
 */
export const CurrentUserQuery = graphql(`
  query CurrentUser {
    currentUser {
      id
      email
    }
  }
`);

/**
 * Sign in with an email and password. Mutates server state (a stored token),
 * so it is exposed as a mutation even though the underlying Ash action is a
 * read (`sign_in_with_password`).
 */
export const SignInWithPasswordMutation = graphql(`
  mutation SignInWithPassword($email: String!, $password: String!) {
    signInWithPassword(email: $email, password: $password) {
      id
      email
      token
    }
  }
`);
