.. A new scriv changelog fragment.

Fixed
-----

- Custom domains with no uploaded logo no longer show the platform's site name
  beside the fallback logo, and page titles and social-share meta tags fall back
  to the configured brand name instead of a hardcoded "Onetime Secret". Both
  surfaces now resolve brand identity through the shared resolver, so the
  neutral-safe fallback for private-label installs is applied consistently.
  (#3566)
