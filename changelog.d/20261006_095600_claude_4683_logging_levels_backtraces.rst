.. A new scriv changelog fragment.

Fixed
-----

- Production console logs now truncate exception backtraces to 20 lines.
  A production limit was documented (as 3 lines) but never applied. Set
  ``BACKTRACE_LINES`` to change it, or ``BACKTRACE_LINES=0`` for full
  backtraces. Other environments stay unlimited. Error reports (Sentry)
  and the log file destination keep the full backtrace (#4683).
- The console no longer shortens the exception object itself, only the
  line it prints. The same exception written to a log file or raised
  again keeps its full backtrace (#4683).
- The ``Chores`` and ``CLI`` log levels in the logging config now take
  effect (``info`` by default, previously ``warn``), so ``bin/ots``
  commands print their info lines on stderr. Any category listed under
  ``loggers:`` is now honored, and ``DEBUG_CHORES`` / ``DEBUG_CLI`` work
  (#4683).
