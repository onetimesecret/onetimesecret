.. A new scriv changelog fragment.

Fixed
-----

- The custom-domain logo in the branded masthead now has a meaningful ``alt``
  (the brand/workspace display name) instead of an empty ``alt``, so screen
  readers announce the brand rather than skipping the image.

- The default logo no longer duplicates its ``aria-label`` on the
  non-interactive wrapper ``<div>``; the accessible name now comes solely from
  the keyhole icon inside the link, so assistive tech announces it once.
