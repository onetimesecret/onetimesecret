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
- ``LINK_DOMAINS`` set but yielding no usable host now aborts boot with
  an ``Onetime::ConfigError`` naming both the env var and the config
  path. Two cases: naming no host at all (``LINK_DOMAINS=`` or
  ``LINK_DOMAINS="  "``), and naming only hosts that cannot be parsed
  (``LINK_DOMAINS=links.internal``), which the error echoes back so the
  typo is visible. A list that mixes parseable and unparseable entries
  still boots — the bad entry is dropped and logged, and the pool keeps
  a host to offer. Deliberately the opposite polarity from an empty
  admin host allowlist: an empty link pool silently falling back to the
  canonical domain would hide the typo and put the internal host back in
  the picker — the exact outcome the setting exists to prevent. (#4063)

Fixed
-----

- A request to ``www.<base-domain>`` no longer classifies ``:canonical``
  merely because some ``LINK_DOMAINS`` entry shares that base domain.
  The ``www.`` tolerance applies to the anchor hosts (``site.host``,
  ``features.domains.default``) only; a link-pool member participates in
  classification by exact match alone. Previously, with
  ``LINK_DOMAINS=go.acme.com``, a tenant's registered ``www.acme.com``
  was classified ahead of the custom-domain lookup and silently lost its
  per-domain brand and sign-in configuration. (#4063)
- Secret creation no longer admits a ``share_domain`` the middleware
  would reject. The link-pool check read ``features.domains.link_domains``
  straight out of config, skipping both the ``features.domains.enabled``
  gate and the parsed-host filter, so a pool configured with the domains
  feature off — or containing an unparseable entry — let guests anchor
  secrets on hosts that classify ``:invalid`` and that the picker never
  offers. (#4063)
- The domain-context picker no longer offers the canonical domain while
  the browser is on a tenant-branded host, where selecting it was
  silently ignored and the link was anchored on the branded host
  anyway. (#4063)
- Selecting the canonical domain in the picker is now written through to
  the server session. It previously cleared only ``sessionStorage``,
  leaving ``sess['domain_context']`` naming the previous selection — and
  since the server value is read first, the next page load silently
  reverted the switch. (#4063)
- Host comparisons in the picker are normalized (lowercased,
  port-stripped) on both sides. ``link_domains`` arrives normalized from
  the server while ``canonical_domain``/``site_host`` do not, so a
  canonical host configured with a port was never recognized as a member
  of its own link pool. (#4063)
- Resetting the picker on a tenant-branded host now lands on that host
  rather than on nothing. With ``LINK_DOMAINS`` unset — the default — the
  pool is canonical-only and the canonical entry is not offered from a
  branded host, so the reset cleared ``sessionStorage`` while
  ``sess['domain_context']`` kept naming the previous selection, which
  the next page load restored. A blank domain cannot be written back
  (the endpoint rejects it), and the served host is where links from
  that host are anchored regardless. (#4063)

AI Assistance
-------------

- Claude added the ``link_domains`` config template, the
  ``Onetime::Config.validate_link_domains!`` boot guard, the
  ``.env.reference`` entry, and the test-lane env scrub. (#4063)
- Claude addressed a code review of the branch: the anchor-only ``www.``
  tolerance, the boot guard for an unparseable pool, the gated
  ``DomainStrategy.link_pool_host?`` predicate that secret creation now
  answers from, and the four frontend picker fixes above. (#4063)
