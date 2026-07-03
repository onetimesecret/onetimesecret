.. A new scriv changelog fragment.

Added
-----

- New ``BRAND_LOGO_ALT`` / ``brand.logo_alt`` setting for operator-supplied
  brand-logo alt text; when unset, alt text falls back to an i18n string
  derived from the product name. (#3612)

Changed
-------

- The ``brand:`` config block is now the single authority for brand identity:
  one documented path (``BRAND_PRODUCT_NAME``, ``BRAND_LOGO_URL``,
  ``BRAND_LOGO_ALT``) brands the masthead, outbound emails, page titles, and
  MFA labels. ``BRAND_LOGO_URL`` now drives the masthead operator logo too
  (previously it was email-only); emails only emit absolute http(s) logo URLs,
  degrading to a text-only header otherwise. (#3612)
- The header config is reduced to masthead layout knobs under
  ``site.interface.ui.header.logo`` — ``href`` (``LOGO_LINK``), ``show_name``
  (``LOGO_SHOW_NAME``), and ``prominent`` (``LOGO_PROMINENT``); the env vars
  are unchanged. ``show_name`` unset now means "show the wordmark unless a
  custom brand logo is configured". (#3612)
- Unconfigured installs now present a fully neutral identity — the "Secure
  Links" name and keyhole mark in the masthead, emails, and page titles —
  instead of the old "One-Time Secret" defaults. (#3612)
- TOTP/MFA authenticator entries now use the configured product name as the
  issuer label when ``BRAND_TOTP_ISSUER`` is unset, so renamed installs brand
  new MFA enrollments too. (#3612)

Deprecated
----------

- ``SITE_NAME``, ``LOGO_URL``, and ``LOGO_ALT`` (the
  ``site.interface.ui.header.branding`` path) are deprecated in favor of
  ``BRAND_PRODUCT_NAME``, ``BRAND_LOGO_URL``, and ``BRAND_LOGO_ALT``. Legacy
  values are still honored as fallbacks; boot logs a warning naming the
  replacement but never refuses to start, even under
  ``DEPRECATED_CONFIG_MODE=strict``. (#3612)

Fixed
-----

- The operator/install logo no longer leaks onto tenant custom domains: they
  show their own uploaded logo or the neutral mark, matching the existing
  wordmark guard. (#3612)
