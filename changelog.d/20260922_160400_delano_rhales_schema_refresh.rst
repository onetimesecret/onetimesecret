.. A new scriv changelog fragment.

Fixed
-----

- ``pnpm run dev`` now regenerates hydration schemas before starting, preventing
  stale schemas from causing development responses to fail. ``pnpm run
  schemas:rhales:generate`` works again.
