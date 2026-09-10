Security
--------

- In ``full`` authentication mode, revoked active sessions are denied on
  their next request.

- Full-mode session inactivity and maximum-age deadlines are now enforced on
  every request.

- Sessions created when an invitation is accepted are now visible to session
  management and can be revoked.

- Requests to sign-up, password reset, magic link, passkey, and SSO routes
  proceed as signed out after a revoked session is presented.
