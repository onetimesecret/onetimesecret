.. A new scriv changelog fragment.

Fixed
-----

- The full-mode integration suite is now green regardless of the ambient
  ``DOMAINS_ENABLED`` environment: specs that need the custom-domain axis
  declare it themselves (new ``'domains enabled'`` shared context), the test
  config installs a parseable canonical host whenever the axis is on, and the
  integration datastore flush runs before group hooks in merged lane runs
  instead of between fixture setup and the request.

Changed
-------

- Rack::Test integration specs reuse one mounted application stack per
  process (``Registry.rack_url_map``), invalidated on registry mutation or a
  config swap, instead of rebuilding every application per example — which
  also reverted class-level middleware state mid-example.

AI Assistance
-------------

- Claude assisted with the ordering triage and the test-harness redesign.
