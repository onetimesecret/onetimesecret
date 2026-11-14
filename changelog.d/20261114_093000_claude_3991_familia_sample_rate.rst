.. A new scriv changelog fragment.

Fixed
-----

- ``FAMILIA_SAMPLE_RATE`` now sets the share of Redis commands written to
  the database command log (``DEBUG_DATABASE=1``). It never applied before.
  Without it, development logs every command, as before. Production does
  not write this log. (#3991)
