// src/shared/composables/helpers/signupHelpers.ts

/**
 * Helper functions for useAuth.signup
 */

import type { CreateAccountSuccess } from '@/schemas/api/auth/responses/auth';
import { CHECK_EMAIL_STATE_KEY } from '@/shared/constants/checkEmail';
import type { RouteLocationPathRaw } from 'vue-router';

/** What the signup form submitted. `redirect` is already validated. */
export interface SubmittedSignup {
  email: string;
  product?: string;
  interval?: string;
  redirect?: string;
}

/**
 * The plan and redirect context that rides past signup. It goes in the query,
 * not history state, because it must survive a fresh entry (a new tab, a
 * shared link).
 *
 * Prefer the server-validated plan intent. Simple-mode responses do not carry
 * billing_redirect, so retain the submitted pair as a fallback and let the
 * login response validate it before checkout. A billing_redirect marked
 * invalid drops the pair.
 */
function carriedQuery(
  response: CreateAccountSuccess,
  submitted: SubmittedSignup
): Record<string, string> {
  const query: Record<string, string> = {};
  const verdict = response.billing_redirect;

  if (verdict?.valid) {
    query.product = verdict.product;
    query.interval = verdict.interval;
  } else if (!verdict && submitted.product && submitted.interval) {
    query.product = submitted.product;
    query.interval = submitted.interval;
  }
  if (submitted.redirect) {
    query.redirect = submitted.redirect;
  }
  return query;
}

/**
 * Where a successful signup goes next, from the server's next_action.
 *
 * sign_in: the account is open but still signed out. Carry the plan/redirect
 * context through sign-in; navigateAfterAuth follows it to checkout or the
 * requested internal destination afterwards.
 *
 * verify_email: the sign-in form is unusable until the account is verified,
 * so route to a dedicated confirmation page. The email travels in router
 * history state, NOT the URL: it is PII, and a query string would leak it
 * through browser history, Referer headers and logs.
 *
 * @param response - the validated create-account success body
 * @param submitted - the email, plan pair and redirect the form sent
 * @returns the location to push
 */
export function signupDestination(
  response: CreateAccountSuccess,
  submitted: SubmittedSignup
): RouteLocationPathRaw {
  const query = carriedQuery(response, submitted);
  const withQuery = Object.keys(query).length > 0 ? { query } : {};

  switch (response.next_action) {
    case 'sign_in':
      return { path: '/signin', ...withQuery };
    case 'verify_email':
      return {
        path: '/check-email',
        ...withQuery,
        state: { [CHECK_EMAIL_STATE_KEY]: submitted.email },
      };
  }
}
