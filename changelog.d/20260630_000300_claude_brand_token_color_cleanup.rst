.. A new scriv changelog fragment.

Fixed
-----

- Replaced hardcoded OneTimeSecret brand colors with brand design tokens so they
  follow per-domain branding (and stay neutral on private-label deployments)
  instead of leaking OTS colors:

  - The disabled-homepage (V1) eyebrow dot now uses the resolved
    ``primaryColor`` instead of a hardcoded OTS orange (``#dc4a22``).
  - ``GlobalBroadcast`` / ``MovingGlobules`` decorative gradients now use the
    ``--color-brand-*`` tokens instead of hardcoded ``#23b5dd`` / ``#3B82F6`` /
    ``#dbeafe``.
  - ``SplitButton`` falls back to ``var(--color-brand-500)`` for its shadow
    color instead of a hardcoded ``rgb(59, 130, 246)`` literal, so runtime
    brand overrides apply.
