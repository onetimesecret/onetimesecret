.. A new scriv changelog fragment.

Fixed
-----

- ``FAMILIA_SAMPLE_RATE`` now sets the share of Redis commands written to
  the database command log (``DEBUG_DATABASE=1``). It never applied before.
  Without it, every command is logged, as before. Production does not write
  this log. A value that is not a number of 0 or more is ignored with a
  warning. (#3991)
