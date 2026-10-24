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
  navigation and is logged rather than reloading the tab in a loop; the page
  then says so and offers a reload button, since the clicked link would
  otherwise seem to do nothing. From the
  moment a reveal is requested until the revealed secret, the one-time
  generated value on a receipt, or a fresh set of MFA recovery codes leaves
  the screen, the page never reloads itself, whatever the cause: the server
  has already destroyed or replaced the value, so the copy in that tab is
  the only one. A failed chunk there falls back to showing the source as
  plain text, and an ended or replaced session shows the stale-session
  notice with its reload button instead of reloading.
