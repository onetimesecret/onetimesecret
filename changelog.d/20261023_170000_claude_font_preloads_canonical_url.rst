Fixed
-----

- Reduced font preloads on server-rendered pages to avoid unnecessary
  downloads and unused-font preload warnings.

- Canonical links now include the page URL, without query parameters,
  instead of an empty ``href``. ``og:url`` and ``twitter:url`` carry the
  same URL, and ``twitter:domain`` names the served host, so pages on a
  custom domain no longer point social scrapers at the install's site.

- Secret and receipt pages (``/secret/*``, ``/receipt/*``,
  ``/incoming/:receiptKey``) send ``noindex, nofollow`` and neutral Open
  Graph text, so a link pasted into a chat unfurls without naming the page,
  and search engines never list it. The text addresses the recipient on a
  secret link and the sender on a receipt. The partial for this existed but
  was not wired to any page.

- Canonical, ``og:url`` and ``twitter:url`` keep the public port of a
  deployment served on a non-default port behind a trusted proxy.
