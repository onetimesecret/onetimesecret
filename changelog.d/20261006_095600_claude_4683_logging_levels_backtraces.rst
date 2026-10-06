.. A new scriv changelog fragment.

Fixed
-----

- With ``BACKTRACE_LINES`` set, the console no longer shortens the
  exception object itself, only the line it prints. The same exception
  written to a log file or raised again keeps its full backtrace (#4683).
