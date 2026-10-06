.. A new scriv changelog fragment.

Added
-----

- The logging config has a ``destinations`` block: an optional log file
  (``destinations.file``, off by default) next to the console, each with
  its own ``level`` and ``formatter``. Category levels still decide which
  events are generated; a destination level only filters what that
  destination writes. The defaults are unchanged: stdout for servers,
  stderr for ``bin/ots``, no file (#4683).
