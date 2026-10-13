.. A new scriv changelog fragment.

Added
-----

- Every run of "Check saved configuration" on a domain's SSO settings is
  recorded in the operator audit trail (``sso.diagnostics_run``): who ran
  it, on which domain, the verdict, and each check's status and error
  code. The entry never includes the client secret, a token or the
  identity provider's message.
- The saved-configuration check and the last sign-in outcome on the domain
  SSO settings are translated in all 29 supported locales.

Changed
-------

- The ``omniauth_failure`` log line for a sign-in through a custom domain
  now carries the domain's id, so a failed tenant sign-in can be tied to
  the domain whose owner asks about it.
