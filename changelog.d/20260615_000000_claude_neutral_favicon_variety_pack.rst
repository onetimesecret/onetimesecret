.. A new scriv changelog fragment.

Added
-----

- Mobile/social favicon "variety pack": the HTML head now emits an SVG favicon,
  Apple touch icon, PWA web manifest + icons, Safari pinned-tab mask icon, and
  Open Graph / Twitter ``og:image``. Per-custom-domain favicons continue to
  take precedence (#3048, #3049).

Changed
-------

- Updated the favicon/icon/social defaults to be brand-neutral. Regenerate
  with ``pnpm gen:favicons``.
