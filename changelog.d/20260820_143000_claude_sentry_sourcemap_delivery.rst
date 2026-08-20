.. A new scriv changelog fragment.

Fixed
-----

- Frontend stack traces in Sentry were never symbolicated, on any release
  built here. The workflow ran ``sentry-cli sourcemaps upload
  ./public/web/dist`` on the runner, but the frontend is compiled *inside* the
  image (the Dockerfile ``build`` stage runs ``pnpm run build``) and
  ``public/web/dist`` is gitignored, so that directory has never existed at
  that point in the job. ``sentry-cli`` treats an empty directory as a
  successful upload of zero artifacts, so every build reported green while the
  frontend project held zero artifact bundles — on every release ever built,
  across every frontend and backend project. The assets are now extracted from
  the image that was just pushed rather than rebuilt: vite emits
  content-hashed filenames, so a second build would produce artifacts named
  for files no browser ever requests — green, and just as useless.

Added
-----

- CI now reports whether telemetry actually shipped. ``continue-on-error`` is
  correct for these steps — telemetry plumbing must never fail a production
  image build — but it makes each step's exit code meaningless as a signal, so
  a green check said nothing about whether anything arrived. Every Sentry step
  now records through ``scripts/ci/sentry-status.sh``, which emits a GitHub
  annotation and a row in a job-summary table that survives after the check
  turns green. The states are deliberately split: SKIPPED (no credentials —
  the normal state of a fork, and silent), BLOCKED (credentials configured but
  a precondition failed) and FAILED (credentials configured and the command
  errored).

- ``scripts/ci/sentry-sourcemap-preflight.sh`` runs the pre-upload assertions
  that were missing: dist tree present, ``.map`` files present, admin bundle
  present, release matching ``__SENTRY_RELEASE__``, and the upload's project
  and dist matching what a frontend event actually reports.

- ``scripts/ci/sentry-verify-artifacts.sh`` asks the *server* after the
  upload. Input checks and exit codes were both satisfiable while the project
  held zero artifact bundles, which is exactly what it held; only a post-upload
  query of the artifact listing distinguishes a real delivery from a
  successful-looking one. Zero artifacts after an upload is reported FAILED.
  This is the only check that would have caught the original defect.

Removed
-------

- ``SENTRY_DIST`` is gone from ``.env.reference``. Nothing in ``lib/``,
  ``apps/`` or ``src/`` ever read it and the preflight never checked it; the
  dist tag is a build-time literal, and an entry in the operator env file read
  like a knob that could change it while offering no way to actually set it.

Documentation
-------------

- The ``dist`` join key is now documented where both of its halves are set.
  Sentry resolves an artifact bundle only when release *and* dist both match.
  This upload has always passed ``--dist=frontend`` while every sampled event
  carried ``dist: null`` — a second, independent reason symbolication could
  not have worked even if the upload had ever shipped a file. **This branch
  fixes only CI's half.** The frontend half lands separately, as
  ``dist: 'frontend'`` in ``src/plugins/core/enableDiagnostics.ts``; until it
  does, the preflight reports the mismatch as an explicit dist-tag warning on
  every run instead of staying silent. Neither merge order breaks anything
  that currently works, and both are required before a frame symbolicates.

- **New, optional CI secret:** ``SENTRY_FRONTEND_PROJECT`` (default
  ``frontend``) names the project the sourcemap upload targets. It must be one
  of ``SENTRY_PROJECTS``, or the release and its artifact bundles land in
  different projects and symbolication silently fails again.

AI Assistance
-------------

- Claude diagnosed the sourcemap-delivery failure — including the finding that
  the frontend project had held zero artifact bundles for every release in its
  history — and wrote the preflight, extraction, status-reporting and
  server-side verification scripts.
