.. A new scriv changelog fragment.

Fixed
-----

- Production logs now truncate exception backtraces to 3 lines, as
  documented. The default never applied; set ``BACKTRACE_LINES`` to
  change it. Error reports (Sentry) keep the full backtrace (#4683).
- The ``Chores`` and ``CLI`` log levels in the logging config now take
  effect (``info`` by default, previously ``warn``), so ``bin/ots``
  commands print their info lines on stderr. Any category listed under
  ``loggers:`` is now honored, and ``DEBUG_CHORES`` / ``DEBUG_CLI`` work
  (#4683).
