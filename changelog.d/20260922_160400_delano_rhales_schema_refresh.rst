.. A new scriv changelog fragment.

Changed
-------

- ``pnpm run dev`` regenerates a checkout's hydration schemas
  (``public/schemas/*.json``) before starting, when the checkout has them.
  Schemas generated before the bootstrap payload changed made the
  development backend answer ``500`` for every page; the schemas are closed,
  so any new payload field has the same effect. ``pnpm run
  schemas:rhales:generate`` works again (it reported "No schema sections
  found").

Removed
-------

- ``apps/web/core/templates/error.rue`` and ``Core::Views::Error``. The
  template did not parse, so its schema was never generated, and nothing has
  rendered it since error pages moved to the Vue entry point (October 2025).
  A spec now parses every Web Core template.
