.. A new scriv changelog fragment.

Removed
-------

- The development-only domain context override is gone: the
  ``DOMAIN_CONTEXT_ENABLED`` and ``DOMAIN_CONTEXT`` environment variables,
  the ``development.domain_context_enabled`` config key and the
  ``O-Domain-Context`` request header are no longer read. It was off by
  default. Remove the variables and the config key from local setups; to
  exercise a custom domain in development, send the request with that
  domain as its host. (#4220)
