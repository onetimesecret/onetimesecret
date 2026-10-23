.. A new scriv changelog fragment.

Changed
-------

- The frontend is built in one Vite pass with code splitting: the customer
  and admin entries share chunks, and each lazy route loads its own chunk on
  first visit. The production ``script-src`` stays nonce-only. Imported
  chunks inherit the entry script's nonce, and the server shell now emits
  the ``csp-nonce`` meta tag and nonced ``modulepreload`` links for the
  preloads that do not inherit it. ``pnpm run build`` and ``build:local``
  are single commands again, and ``.vite/manifest-admin.json`` is gone.

- A lazy chunk that fails to load reloads the page once, through the same
  one-per-tab-per-minute bound as the stale-session reload (ADR-046),
  instead of on every failure. A chunk that keeps failing now fails its
  navigation and is logged rather than reloading the tab in a loop.
