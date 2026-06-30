.. A new scriv changelog fragment.

Fixed
-----

- The neutral default logo (``DefaultLogo``) and the unbranded fallback mark on
  the disabled-homepage variants now render the brand-neutral keyhole, matching
  the favicon generator. Previously they rendered the Japanese "maruhi" (秘)
  mark, which is OneTimeSecret company branding and must not appear in
  private-label / custom-domain contexts (#3048, #3049).

Removed
-------

- Removed the orphaned ``KeyholeLogo.vue`` component; ``DefaultLogo`` is now the
  canonical neutral keyhole logo.

Changed
-------

- The "Colonels Only" badge in the logo components is now localized
  (``web.layout.colonels_only_badge``).
