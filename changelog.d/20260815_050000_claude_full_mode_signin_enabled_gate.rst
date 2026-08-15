.. A new scriv changelog fragment.

Fixed
-----

- Full mode now enforces a custom domain's per-domain sign-in opt-in on the
  password and email (magic-link) authentication routes. ADR-024 specifies
  that custom domains are default-OFF for password/email sign-in and become
  available only when the domain owner explicitly opts in with an enabled
  ``SigninConfig``. That rule was enforced in simple mode (where Core serves
  the sign-in POST), on the display surfaces (the branded masthead link and
  the ``/signin`` page availability verdict) and in the settings API — but in
  full mode, where Rodauth serves those routes, nothing consulted it. A custom
  domain that had never opted in, or that had explicitly opted out, could
  still complete a password sign-in. The opt-in is now applied on the same
  ``before_rodauth`` chokepoint as ``restrict_to``, using the same
  model-owned resolver (``SigninConfig.resolve_signin_enabled_for_request``)
  the other surfaces already use, so display and runtime cannot disagree.

  This narrows, it does not close: a domain that has opted in signs in
  exactly as before, operator (canonical/subdomain) hosts follow the install's
  global settings unchanged, and logout, the second-factor ceremony and
  account-scoped routes are untouched. SSO is deliberately not gated by this
  flag — it is the password/email opt-in, and an SSO-only tenant sets it off
  precisely to disable passwords — so tenant SSO sign-in is unaffected.

  A rejected route answers ``404`` with the router's shared not-found body,
  identical to an undefined route, per
  ADR-034#reject-as-not-found-not-forbidden. If the per-domain policy itself
  cannot be read (a datastore failure), the answer is ``503`` rather than a
  fail-closed ``404``, matching the existing ``restrict_to`` gate: the request
  is still denied, but an unreadable policy is reported as an outage instead
  of being disguised as a route that does not exist.

AI Assistance
-------------

- Claude added the full-mode availability gate (``Auth::SigninEnabled``) as a
  sibling of ``Auth::RestrictTo``, wired it into the existing
  ``before_rodauth`` / ``before_email_auth_request`` hooks, and added
  integration coverage for the opted-out and never-configured custom-domain
  cases along with the narrowing and non-gated surfaces.
