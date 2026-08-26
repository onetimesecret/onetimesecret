.. A new scriv changelog fragment.

Changed
-------

- The customer JS bundle no longer carries every translation. Only English
  ships inside it; the other locales are built as standalone JSON assets and
  the page fetches the one it needs. That takes the bundle from 2.66 MB to
  695 KB gzipped — a 74% cut to the bytes a secret link recipient waits on
  before the page can render. If a locale asset fails to load the page still
  renders, in English. (#4288)

- The page no longer preloads fonts. It used to preload every font in the
  build — eight files, roughly 675 KB, at the browser's highest fetch
  priority — ahead of the assets the page cannot paint without. The faces now
  load at normal priority with ``font-display: swap``, so text appears
  immediately in the fallback serif and restyles when Zilla Slab arrives.
  (#4288)

AI Assistance
-------------

- Diagnosis and implementation of the secret link render path work assisted
  by Claude. (#4288)
