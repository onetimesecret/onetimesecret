.. A new scriv changelog fragment.

Changed
-------

- Custom-domain homepages no longer show the **Create Account** and **Sign In**
  nav links by default. The per-domain ``signup_enabled`` / ``signin_enabled``
  toggles on ``CustomDomain::HomepageConfig`` now default to *off*, matching the
  conservative default of the sibling ``SigninConfig`` / ``SignupConfig``
  models, so recipients and employees arriving via a shared secret link no
  longer see account chrome that isn't meant for them. Operators re-enable the
  links per domain via ``PUT /homepage-config`` (domain homepage settings). The
  authentication kill switch (``resolve_signin_enabled`` /
  ``resolve_signup_enabled`` and the serializer's ``effective_*`` gates) is
  unchanged — this only narrows what is displayed, never widens capability.
  (#3618)

- **Action Required**: existing custom domains have these flags persisted as
  ``true`` (written by ``CustomDomain.create!`` and the #3023 backfill), so a
  code-only default change cannot reach them. A data migration resets the stored
  values to ``false``; run it during deployment::

      bin/ots migrate --run 20260703_01_disable_homepage_auth_links

  The migration is idempotent (already-off records are skipped) and preserves
  each domain's homepage ``enabled`` (public secret form) setting. (#3618)
