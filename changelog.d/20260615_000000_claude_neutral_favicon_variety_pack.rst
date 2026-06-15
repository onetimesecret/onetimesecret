.. A new scriv changelog fragment.

Added
-----

- Mobile/social favicon "variety pack": the HTML head now emits an SVG favicon,
  Apple touch icon, PWA web manifest + icons, Safari pinned-tab mask icon, and
  Open Graph / Twitter ``og:image``. Operators can override per asset with
  ``BRAND_FAVICON_URL``, ``BRAND_APPLE_TOUCH_ICON_URL``, and
  ``BRAND_OG_IMAGE_URL``, by dropping replacement files into ``docker/branding/``
  at build time, or by mounting over ``public/web`` at runtime. Per-custom-domain
  favicons continue to take precedence. (#3048, #3049)

Changed
-------

- Shipped favicon/icon/social defaults are now brand-neutral (a generic keyhole
  mark on neutral blue) instead of the One-Time Secret brand, so a self-hosted
  install never serves the company favicon by default. Regenerate or re-skin the
  set with ``scripts/branding/``.

Removed
-------

- Removed the unreferenced One-Time Secret-branded ``favicon.svg``,
  ``favicon.png``, and ``social-preview.png`` from ``public/web/img`` (and the
  duplicate ``v3/img/favicon.svg``); the neutral document-root pack replaces them.

Documentation
-------------

- Added ``docs/customization/branding-favicon.md`` and a variety-pack section to
  ``docs/architecture/branding.md`` covering the favicon override precedence and
  build-time vs. runtime customization.
