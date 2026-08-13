.. A new scriv changelog fragment.

Changed
-------

- (`#4157 <https://github.com/onetimesecret/onetimesecret/issues/4157>`_)
  Sign-in and sign-up availability now requires a positively classified
  operator host. The request's domain classification is passed to the
  resolvers (``SigninConfig.resolve_signin_enabled_for_request`` /
  ``SignupConfig.resolve_signup_enabled_for_request``), and the install's
  global defaults are applied only on ``:canonical`` or ``:subdomain``.
  Anything else — including a request whose classification could not be
  established — takes the default-OFF custom-domain resolver, so a domain
  the app cannot positively place as its own never inherits operator
  defaults. Previously the branch was chosen by testing "is this exactly a
  custom domain?", whose false side is wider than it reads. The display gate
  (``ConfigSerializer#resolve_signin``) moves with the runtime gates, so the
  ``/signin`` page and the POST handler continue to agree, and the tenant-SSO
  display carve-out is unchanged.

  Operator note: this is fail-closed. While the custom-domain datastore is
  unreachable, a recognized operator **subdomain** can be held to the
  stricter default, since its classification is established after that read.
  The canonical host is unaffected — it classifies before any datastore
  access. Nothing that was explicitly enabled on a domain is withdrawn.

  Domain identity is unchanged: ``custom_domain_request?`` and
  ``tenant_domain?`` remain exact custom-domain tests, so branding, favicon
  and routing behavior for unknown hosts is the same as before.

- (`#4157 <https://github.com/onetimesecret/onetimesecret/issues/4157>`_)
  Platform SSO providers are withheld from any host that is not positively an
  operator host when ``allow_platform_fallback_for_tenants`` is off. The
  fallback policy previously applied only to hosts classified exactly as
  custom domains, so a host the app could not place was offered providers the
  operator had withheld from tenants. Installs that permit platform fallback
  are unaffected.

- (`#4157 <https://github.com/onetimesecret/onetimesecret/issues/4157>`_)
  An unreadable per-domain sign-up policy now answers 503 instead of 500, on
  the same terms as the existing sign-in behavior: operator hosts, whose
  policy is entirely in-memory configuration, are unaffected and continue to
  follow the global setting. Autoverify resolution takes the same rule, rather
  than falling back to the install-wide setting for a tenant whose own
  configuration could not be read.

Documentation
-------------

- (`#4157 <https://github.com/onetimesecret/onetimesecret/issues/4157>`_)
  ADR-024 gains amendment A12, recording the rule (operator defaults require
  positive evidence), why the domain identity predicates were deliberately
  not redefined, the fail-closed availability cost, and the display/runtime
  parity requirement. The ``DomainStrategy`` consumer table now groups its
  consumers by which test they use.

AI Assistance
-------------

- Claude added the request-aware sign-in/sign-up resolvers and repointed the
  runtime and display gates at them, wrote ADR-024 A12, and regrouped the
  ``DomainStrategy`` consumer table. (#4157)
