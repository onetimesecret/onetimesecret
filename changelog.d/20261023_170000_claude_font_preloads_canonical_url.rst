Fixed
-----

- Reduced font preloads on server-rendered pages to avoid unnecessary
  downloads and unused-font preload warnings.

- Canonical links now include the page URL, without query parameters,
  instead of an empty ``href``. ``og:url`` and ``twitter:url`` carry the
  same URL, and ``twitter:domain`` names the served host, so pages on a
  custom domain no longer point social scrapers at the install's site.

- Secret and receipt pages (``/secret/*``, ``/receipt/*``) send
  ``noindex, nofollow`` and neutral Open Graph text, so a link pasted into a
  chat unfurls without naming the page, and search engines never list it.
  The partial for this existed but was not wired to any page.
