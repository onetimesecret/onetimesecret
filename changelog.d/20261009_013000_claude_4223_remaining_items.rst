.. A new scriv changelog fragment.

Security
--------

- A member whose organization membership is scoped to one custom domain
  (as tenant SSO grants it) can no longer list another domain's receipts
  with ``scope=domain``, nor the organization-wide receipt list
  (``scope=org``) or secret activity trail; both read across every domain of
  the organization. The ``audit_logs`` entitlement alone admitted such a
  member. (RISK-2026-08-14-M06)

Changed
-------

- The favicon, the domain serializer and the sign-up policy read use the
  CustomDomain record the request already resolved instead of looking the
  display domain up again. A failed read still fails the sign-up policy
  closed on a tenant host. (#4220)

- The ``.env.reference`` entries for ``PUBLIC_HOST_REWRITE`` and ``SMTP_SSL``
  record v0.26.15 as the release they shipped in.
