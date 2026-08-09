.. A new scriv changelog fragment.

Added
-----

- ``LINK_DOMAINS`` (``features.domains.link_domains``) — a
  comma-separated list of hosts offered in the link-domain picker. For
  installs whose canonical host is an internal platform address that
  must keep serving the app but must never be offered to customers as a
  link domain. Unset, the picker offers the canonical domain, so every
  existing install is unchanged. Set, the picker offers exactly the
  listed hosts and every entry also joins the canonical host set, so
  requests to them serve rather than classifying ``:invalid``. (#4063)
- ``LINK_DOMAINS`` set but naming no host (``LINK_DOMAINS=`` or
  ``LINK_DOMAINS="  "``) now aborts boot with an
  ``Onetime::ConfigError`` naming both the env var and the config path.
  Deliberately the opposite polarity from an empty admin host
  allowlist: an empty link pool silently falling back to the canonical
  domain would hide the typo and put the internal host back in the
  picker — the exact outcome the setting exists to prevent. (#4063)

AI Assistance
-------------

- Claude added the ``link_domains`` config template, the
  ``Onetime::Config.validate_link_domains!`` boot guard, the
  ``.env.reference`` entry, and the test-lane env scrub. (#4063)
