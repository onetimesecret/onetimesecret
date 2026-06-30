.. A new scriv changelog fragment.

Fixed
-----

- The V3 brand settings schema now defaults ``button_text_light`` to ``true``,
  matching the canonical contract and ``NEUTRAL_BRAND_DEFAULTS``. A ``false``
  default silently shadowed the identity store's fallback, so unbranded domains
  rendered dark button text instead of the intended light text.
- The branding live-preview now resets ``button_text_light`` to the default when
  the primary color is cleared, instead of keeping the stale contrast decision
  from the previous color.

Changed
-------

- ``useBrandTheme`` now no-ops when there is no DOM (SSR/prerender guard),
  matching the window guards used elsewhere in the codebase.
