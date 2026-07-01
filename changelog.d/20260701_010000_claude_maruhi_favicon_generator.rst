.. A new scriv changelog fragment.

Added
-----

- The favicon generator (``scripts/branding/``) is now a reusable, fully
  parameterized tool. The glyph (``MARK_PATH`` + ``MARK_NATIVE_WIDTH`` /
  ``MARK_NATIVE_HEIGHT``), palette (``MARK_PRIMARY_COLOR``,
  ``MARK_BACKGROUND_COLOR``, ``MARK_OG_GRADIENT_DARK``), manifest name
  (``MARK_PRODUCT_NAME`` / ``MARK_SHORT_NAME``), glyph sizing (``MARK_COVERAGE``
  and friends), and an optional license credit (``MARK_ATTRIBUTION``, embedded as
  an SVG comment) are all overridable without editing the source. Named override
  bundles live as presets in ``scripts/branding/presets/`` and are selected with
  ``--preset <name>`` (shell-portable) or the ``MARK_PRESET`` env var. Preset
  names are validated against path traversal and unknown keys are reported, and a
  dependency-free test suite (``pnpm run gen:favicons:test``) covers the pure
  logic.

- Optional Onetime Secret company-brand favicon pack, ``pnpm run
  gen:favicons:maruhi``, ships as the first preset: it renders the "maruhi" mark
  (circled 秘 "secret" glyph) in the current logo's orange/white palette
  (``OnetimeSecretIcon.vue`` / onetime-logo-v3) through the shared generator, no
  separate code path. Writes the deployable pack to ``docker/public/`` and a
  reviewable source copy to ``src/assets/branding/maruhi/``, leaving the
  brand-neutral defaults in ``public/web/`` untouched (#3048, #3049).

Fixed
-----

- ``scripts/branding/mark.mjs``'s ``MARK_PATH`` glyph override silently
  mis-scaled and mis-centered any glyph whose native size wasn't the keyhole's
  512x1024. The native bounds are now configurable via ``MARK_NATIVE_WIDTH`` /
  ``MARK_NATIVE_HEIGHT``, so custom-glyph packs render correctly.
