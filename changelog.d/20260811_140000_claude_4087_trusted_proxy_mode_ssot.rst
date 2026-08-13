.. A new scriv changelog fragment.

Fixed
-----

- **Operators:** the startup ``trusted_proxy:`` posture line now reports the
  mode actually in force instead of echoing the configured string back. The
  admin-isolation boot diagnostics and the code that configures client-IP
  resolution used to read ``TRUSTED_PROXY_MODE``
  (``site.network.trusted_proxy.mode``) independently, with different
  expressions, so a deployment configured ``TRUSTED_PROXY_MODE=Depth`` ran
  filter — the resolution branch tests for the exact string ``depth`` — while
  announcing ``trusted_proxy: enabled (mode=Depth)`` on the one line operators
  are told to read to confirm the posture of the gates protecting the admin
  surfaces. Both now read one accessor: the mode is matched
  case-insensitively and canonicalized, and the posture line always names the
  mode the request path will use. (#4087)

- **Operators — action may be required on upgrade.** If your
  ``TRUSTED_PROXY_MODE`` means depth but is not written as exactly ``depth``,
  this release changes how client IPs are resolved. ``Depth``, ``DEPTH`` and
  ``  depth  `` previously
  failed the exact-string test and ran **filter**; they are now canonicalized
  and genuinely select **depth**, which counts hops from the right of the
  forwarded chain — a different address, and a wrong one if
  ``TRUSTED_PROXY_DEPTH`` does not match the real proxy topology. Boot now
  logs a warning naming both the configured and the canonicalized value when
  this applies. Other rewritten spellings — ``FILTER``, ``  filter  `` — ran
  filter before and run filter now; they get a separate, milder boot line that
  does not claim a behaviour change. Check before upgrading that ``TRUSTED_PROXY_DEPTH`` matches
  your actual hop count: a mismatch resolves a proxy or CDN address as the
  client, which affects admin CIDR enforcement and shares rate-limit buckets
  across unrelated clients. Setting ``TRUSTED_PROXY_MODE=filter`` explicitly
  preserves the behaviour you were actually running. (#4087)

Changed
-------

- **Operators:** an unrecognized ``TRUSTED_PROXY_MODE`` now WARNs at boot
  naming the value and the mode actually running, instead of silently
  falling through to filter. The accepted set is closed (``filter``,
  ``depth``), matching how ``TRUSTED_PROXY_HEADER`` is already documented. A
  typo such as ``dept`` still runs filter — the safer of the two, since it
  authenticates each forwarded hop against the trusted-proxy CIDR set — and
  still boots: a configuration whose misreading already fails closed should
  not take a deployment offline. The warning is emitted once per process
  rather than once per mounted application, and two further distinct warnings
  cover the canonicalization cases above — one for a rewrite that selects depth
  where filter used to run, one for a rewrite that changes nothing. Each is
  tagged separately, so a cosmetic rewrite cannot silence the warning that
  reports a real change. Behaviour for unset, empty and
  exactly-lowercase values is unchanged, and those spellings log nothing.
  (#4087)

AI Assistance
-------------

- Claude consolidated the four independent readers of
  ``site.network.trusted_proxy`` onto the single
  ``MiddlewareStack.trusted_proxy_enabled?`` / ``.trusted_proxy_mode`` pair,
  added the mode canonicalization, closed-set validation and the three boot
  warnings (unrecognized value, rewrite that changes the running mode, and
  rewrite that does not),
  and moved the ``filter`` default out of its three homes into the accessor.
  (#4087)
