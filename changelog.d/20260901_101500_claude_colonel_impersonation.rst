Added
-----

- Colonel console: an **Impersonate** action on the customer detail page. It
  requires a written reason, then turns the operator's existing session into a
  read-only view of the application as that customer for 30 minutes. A banner
  is shown on every page with the customer's email, the time remaining, and a
  **Stop impersonating** button; stopping returns to that customer's detail
  page. Colonel, anonymous, and suspended accounts cannot be impersonated.

- Impersonation is read-only and cannot act on the operator's own account.
  Only page reads are permitted: creating, revealing, or burning secrets,
  changing account settings, credentials, or MFA, billing changes, and the
  colonel console itself are all refused while impersonating. Sign-in and
  account routes are blocked outright because they still resolve to the
  operator's own account, not the customer's.

- Every impersonation is audited at both ends — start (operator, customer,
  reason) and stop, including when it ends by expiry rather than by the
  operator. An impersonation session belongs to the operator throughout: it
  does not appear in the customer's session list, and the customer's session
  controls do not act on it.

- The ``customers impersonate`` CLI verb and the token primitive it was built
  on (#4359) are not shipped. Neither appeared in a release. A shell has no
  verified operator identity to record, which is the one control impersonation
  depends on, so the console — where the operator is authenticated — is the
  only place this is offered.
