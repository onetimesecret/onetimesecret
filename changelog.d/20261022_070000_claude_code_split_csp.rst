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
