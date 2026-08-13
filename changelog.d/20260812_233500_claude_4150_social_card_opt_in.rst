.. A new scriv changelog fragment.

Added
-----

- (`#4150 <https://github.com/onetimesecret/onetimesecret/issues/4150>`_) The
  social card (``og:image`` / ``twitter:image``) can now be turned off entirely
  with ``BRAND_OG_IMAGE_URL=none`` (``off`` / ``false`` also work). The head then
  emits **no** image meta tags at all — never an empty tag, never one pointing at
  a 404 — and ``twitter:card`` degrades from ``summary_large_image`` to
  ``summary``, which renders correctly without an image. Previously there was no
  way to suppress the card: the tag was emitted unconditionally, and a blank
  ``BRAND_OG_IMAGE_URL`` was indistinguishable from an unset one.

Changed
-------

- (`#4150 <https://github.com/onetimesecret/onetimesecret/issues/4150>`_) The
  social card is now resolved from the brand-pack **asset** rather than a
  hardcoded path, so serving and linking can no longer disagree: a pack that
  carries ``social-preview.png`` has it served and linked, and one that carries
  none (with nothing to fall through to) emits no tags instead of pointing at a
  URL that 404s. ``social-preview.png`` moves from the mandatory pack asset set
  to the existence-filtered optional set, alongside the pack-carried masthead
  logo. The tracked ``default`` and example packs still ship a neutral card, so
  a stock install is unchanged.

Fixed
-----

- (`#4150 <https://github.com/onetimesecret/onetimesecret/issues/4150>`_) Custom
  domains no longer inherit the install's social card. ``og:image`` resolves from
  the install's brand config and there is no per-domain social image, so a secret
  link shared from a customer's custom domain previewed with the install
  operator's card. The card is now suppressed unconditionally on custom domains,
  mirroring the existing suppression that keeps the canonical SVG favicon from
  shadowing a domain's own icon.
