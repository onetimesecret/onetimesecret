.. A new scriv changelog fragment.

Added
-----

- All OTS processes (web, scheduler, worker, CLI) now install a ``SIGUSR2``
  heap dump handler at boot. Sending ``kill -USR2 <pid>`` writes an
  ``ObjectSpace.dump_all`` snapshot to ``heap-<pid>-<epoch>.json`` (under
  ``HEAP_DUMP_DIR``, default ``/tmp``) so operators can diagnose RSS vs. Ruby
  heap growth in running production containers without attaching GDB or
  restarting with extra instrumentation. The dump runs in a spawned thread
  (``ObjectSpace.dump_all`` is not signal-safe) and the handler is installed in
  the Puma/Sneakers master and inherited by forked workers. A companion
  ``scripts/analyze-heapdump`` summarizes a dump (object counts by type, bytes
  by type, top STRING allocation sites). (#3366)

Security
--------

- Heap dumps are written owner-only (``0600``) and created exclusively
  (``O_EXCL``) so they cannot clobber or follow a pre-planted symlink in a
  shared ``/tmp``. A dump serializes live String values, so it contains
  plaintext secrets and key material — treat the file as a credential and
  delete it after analysis. (#3366)

AI Assistance
-------------

- Heap dump boot initializer, analysis script, and tests drafted with AI
  assistance. (#3366)
