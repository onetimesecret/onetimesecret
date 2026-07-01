.. A new scriv changelog fragment.

Added
-----

- New optional company-brand favicon generator, ``pnpm run gen:favicons:maruhi``,
  renders the Onetime Secret "maruhi" mark (circled 秘 "secret" glyph) in the
  current logo's orange/white palette (``OnetimeSecretIcon.vue`` /
  onetime-logo-v3). Writes the deployable pack to ``docker/public/`` (the
  existing build-time brand overlay) and a reviewable source copy to
  ``src/assets/branding/maruhi/``. Entirely separate from the brand-neutral
  defaults in ``public/web/``, which are unaffected (#3048, #3049).

Fixed
-----

- ``scripts/branding/mark.mjs``'s ``MARK_PATH`` override (swap the favicon
  generator's glyph without editing the source) silently mis-scaled and
  mis-centered glyphs whose native size wasn't the keyhole's 512x1024. The
  native size is now configurable via ``MARK_NATIVE_WIDTH`` /
  ``MARK_NATIVE_HEIGHT``, so custom-glyph packs render correctly.
