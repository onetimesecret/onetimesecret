.. A new scriv changelog fragment.

Security
--------

- Behind a proxy that rewrites ``Host``, an ``Origin`` naming a host that is
  not a canonical host, a subdomain of one, or a registered custom domain is
  now refused before the application runs; it was admitted whenever it
  matched the detected host. A registered custom domain whose record could
  not be read is still admitted, so the application's own refusal answers.
  A proxy that preserves ``Host`` is unaffected. (#4669)
