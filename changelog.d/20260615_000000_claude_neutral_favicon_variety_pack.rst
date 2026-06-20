.. A new scriv changelog fragment.

Added
-----

- Mobile/social favicon "variety pack": the HTML head now emits an SVG favicon,
  Apple touch icon, PWA web manifest + icons, Safari pinned-tab mask icon, and
  Open Graph / Twitter ``og:image``. Operators can override per asset with
  ``BRAND_FAVICON_URL``, ``BRAND_APPLE_TOUCH_ICON_URL``, and
  ``BRAND_OG_IMAGE_URL``, by dropping replacement files into
  ``docker/branding/public/web/`` at build time, or by mounting over
  ``public/web`` at runtime. Per-custom-domain
  favicons continue to take precedence. (#3048, #3049)
- Brand-aware PWA manifest: ``/site.webmanifest`` is now served by a route that
  overlays ``BRAND_PRODUCT_NAME`` and ``BRAND_PRIMARY_COLOR`` onto the neutral
  manifest, so the Android home-screen install reflects the configured brand.

Changed
-------

- Shipped favicon/icon/social defaults are now brand-neutral (a generic keyhole
  mark on neutral blue) instead of the One-Time Secret brand, so a self-hosted
  install never serves the company favicon by default. The One-Time Secret brand
  assets still ship under ``public/web/img`` for installs (including
  onetimesecret.com and the public OCI image) that opt into them via
  configuration. Regenerate or re-skin the neutral set with ``pnpm gen:favicons``.

Documentation
-------------

- Added ``docs/product/branding-favicon.md`` and a variety-pack section to
  ``docs/architecture/branding.md`` covering the favicon override precedence,
  override surface, and build-time vs. runtime customization.
