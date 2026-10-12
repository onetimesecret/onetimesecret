.. A new scriv changelog fragment.

Security
--------

- ``POST /auth/email-login-request`` (magic links) and
  ``POST /auth/verify-account-resend`` now give the same success answer
  whether or not the submitted address has an account, whether that account
  may use the route, and whether a link was sent recently. Before, an unknown
  address got a 401 and a recently mailed one a 400, which let anyone check
  whether an address was registered. Links are still sent only to existing,
  eligible accounts, and Rodauth's resend windows still apply. An account whose
  link would need a sign-in origin it does not have (a member-less tenant host
  with no ``site.host``) now gets the same answer, with an error logged
  instead of a 500. An unsupported ``locale`` request parameter used to make
  the email for an existing account fail with a 500 on these routes and on
  ``POST /auth/reset-password-request``; auth emails now ignore a locale the
  app does not ship and use the next candidate or the default.
  (RISK-2026-08-14-M03)

  **Upgrade note for API clients**: these two routes no longer return
  ``no_matching_login`` or the "recently sent" error. A client that showed
  "no account found" or "already sent" from those errors now sees the normal
  "email sent" response.
