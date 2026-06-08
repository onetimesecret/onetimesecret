.. A new scriv changelog fragment.

Added
-----

- Opt-in on-demand heap dumps for diagnosing memory growth. When
  ``HEAP_DUMP_ENABLED`` is set (default off), every OTS process (web, scheduler,
  worker, CLI) installs a ``SIGUSR2`` handler at boot; ``kill -USR2 <pid>``
  writes an ``ObjectSpace.dump_all`` snapshot to ``heap-<pid>-<epoch>.json``
  (under ``HEAP_DUMP_DIR``, default ``/var/tmp``) so operators can diagnose RSS
  vs. Ruby heap growth without attaching GDB or restarting with extra
  instrumentation. The dump runs in a spawned thread (``ObjectSpace.dump_all``
  is not signal-safe) and the handler is installed in the Puma/Sneakers master
  and inherited by forked workers. A companion ``scripts/analyze-heapdump``
  summarizes a dump (object counts by type, bytes by type, top STRING
  allocation sites). (#3366)

Security
--------

- Heap dumps are off by default and gated behind ``HEAP_DUMP_ENABLED``: a dump
  serializes live String values, so it contains plaintext secrets and key
  material, and the handler is a memory-disclosure primitive that bypasses the
  default container ptrace restriction. When enabled, dumps are written
  owner-only (``0600``) and created exclusively (``O_EXCL``) so they cannot
  clobber or follow a pre-planted symlink in a shared directory. Treat a dump
  file as a credential and delete it after analysis. (#3366)

AI Assistance
-------------

- Heap dump boot initializer, analysis script, and tests drafted with AI
  assistance. (#3366)
