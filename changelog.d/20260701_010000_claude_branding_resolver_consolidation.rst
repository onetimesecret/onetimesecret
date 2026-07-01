.. A new scriv changelog fragment.

Fixed
-----

- Custom domains with no uploaded logo no longer show the platform site name
  beside the fallback logo, and page titles / social-share meta tags fall back
  to the configured brand name instead of a hardcoded "Onetime Secret". Both
  surfaces now resolve brand identity through the central resolver
  (``identityStore``) instead of re-deriving it from raw bootstrap fields, so
  the neutral-safe fallback is applied in one place. (#3566)

Changed
-------

- The masthead now consumes ``identityStore.productName`` /
  ``showPlatformIdentity``, while the default logo and page-title composable use
  the shared ``resolveProductName`` helper directly — none re-implement the
  ``brand_product_name`` → neutral-default fallback, making private-label
  branding leaks structurally hard rather than caught surface-by-surface.
