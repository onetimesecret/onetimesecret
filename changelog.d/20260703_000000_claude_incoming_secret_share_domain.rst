.. A new scriv changelog fragment.

Fixed
-----

- Incoming secrets submitted on a custom domain (``/incoming``) are now bound to
  that domain. ``CreateIncomingSecret`` created the secret/receipt pair without
  passing ``domain:`` to ``Receipt.spawn_pair``, so ``share_domain`` was left
  nil even though ``domain_id`` was set on the receipt. As a result the
  notification email rendered the canonical host for the secret link, and the
  message was delivered through the default sender config instead of the custom
  domain's mailer config. The domain is now propagated to ``spawn_pair`` so the
  secret link and sender selection match the domain the secret was submitted on,
  bringing the anonymous ``/incoming`` flow in line with the authenticated
  Domain-Context flow.
