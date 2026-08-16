.. A new scriv changelog fragment.

Fixed
-----

- (`#4167 <https://github.com/onetimesecret/onetimesecret/issues/4167>`_)
  An enabled per-domain ``SigninConfig`` that expresses no sign-in opinion —
  ``restrict_to`` unset and ``signin_enabled=false`` — no longer suppresses
  the SSO host pin. The display serializer and the route gate pin ``sso`` as
  the inherited restriction for a custom host reachable only via SSO, and
  both previously skipped that pin whenever any *enabled* config existed for
  the host. Combined with the operator platform-SSO fallback, such a
  no-opinion config resolved ``:unrestricted`` for a host whose only working
  method is SSO, leaving password/email endpoints accepting crafted POSTs on
  that host — the widen direction ADR-034 fail-closed degradation exists to
  prevent. Both pin sites now skip on the new model-owned predicate
  ``SigninConfig.speaks_for_restrict_to?``: a config speaks when it names a
  restriction or opts the password/email methods in; enabled-but-silent
  configs fall through to the pin exactly like the no-config case. A config
  with ``signin_enabled=true`` and no ``restrict_to`` still resolves
  unrestricted — the owner explicitly opted the non-SSO methods in.

AI Assistance
-------------

- Claude added ``SigninConfig.speaks_for_restrict_to?`` and repointed both
  SSO host-pin sites at it, with unit and display/gate parity coverage.
  (#4167)
