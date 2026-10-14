.. A new scriv changelog fragment.

Added
-----

- Every run of "Check saved configuration" on a domain's SSO settings is
  recorded in the security audit trail (``sso.diagnostics_run``): who ran
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

Security
--------

- Actions a customer takes on their own account, workspace or domain are
  now recorded in the security audit trail instead of the operator audit
  trail: confirming an email change (including a refused or repeated
  confirmation), deleting a workspace, and sending a domain test email.
  Each can be repeated at will, and the operator trail keeps a fixed number
  of entries, so a long run of them could push out older operator entries.
  The admin console keeps these entries for 7 days (newest 1,000); the
  ``ColonelAudit`` log stream still carries every one. The same actions
  taken by an operator, including a colonel using the customer-facing
  pages, still go to the operator trail. Test-email entries now store the
  recipient address obscured.
- "Send test" on a domain's email sender settings is now limited per
  account: 10 test emails per hour by default, then a one-hour wait
  (``SENDER_TEST_EMAIL_RATE_LIMIT_*``; kind ``sender_test_email`` for
  ``bin/ots ratelimit`` and the admin reset). The form says how long to
  wait. Each send is a real email through the delivery provider and one
  audit entry, so an unlimited loop could fill the security audit trail.
