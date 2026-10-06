.. A new scriv changelog fragment.

Added
-----

- ``tests/lanes/run`` can keep a test run's application log in a file.
  ``--capture-logs`` writes ``app.log`` in the lane's run directory
  (``tmp/lanes/<lane>/<overlays>/``) and the emails the logger mail backend
  delivers to ``mail.log`` beside it. ``--log-console <off|level>`` filters
  what the application's log prints on the console; no log level is raised,
  so the file keeps the expected error-level events. ``--quiet`` now works
  together with an RSpec results file. CI runs every lane this way and
  uploads ``app.log`` and the console transcript as a ``lane-logs-*``
  artifact, kept for 3 days. See ``tests/lanes/README.md`` (#4683).

Fixed
-----

- ``tests/lanes/run`` no longer sources the caller's ``~/.bashrc`` into
  the test processes when its standard input is a socket (an agent
  harness, a command over ssh) (#4683).
- A lane ``env`` file or overlay that sets one of the runner's own
  variables (``QUIET``, ``CAPTURE_LOGS``, ``LOG_CONSOLE``, ...), or a
  ``SPEC_OPTS`` that selects a formatter, now exits 64 instead of changing
  the run without a flag (#4683).
- The CI aggregate report names an RSpec results file that is empty or not
  JSON instead of reading it as an empty suite (#4683).
