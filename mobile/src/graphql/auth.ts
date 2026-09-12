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
 * Requests a magic-link sign-in token be sent to the given email. Always
 * reports the same success result whether or not the email is registered,
 * so it can never be used to enumerate accounts. A first-ever sign-in for
 * an email registers the account.
 */
export const RequestMagicLinkMutation = graphql(`
  mutation RequestMagicLink($email: String!) {
    requestMagicLink(email: $email)
  }
`);

/**
 * Exchanges a magic-link token (from `RequestMagicLinkMutation`) for a
 * bearer JWT. The token can only be used once.
 */
export const SignInWithMagicLinkMutation = graphql(`
  mutation SignInWithMagicLink($token: String!) {
    signInWithMagicLink(token: $token) {
      result {
        id
        email
      }
      metadata {
        token
      }
      errors {
        message
        fields
        code
      }
    }
  }
`);
