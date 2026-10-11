.. A new scriv changelog fragment.

Added
-----

- Custom domain homepage settings gain network rules: an allowed list and a
  denied list of IPv4/IPv6 addresses or CIDR ranges. When either list is
  set, visitors in a denied range, or outside every allowed range, see the
  domain's private landing page and are refused anonymous secret creation,
  exactly as if the homepage were disabled. Both lists are empty by default,
  so existing domains are unaffected. The rules are edited in the workspace
  domain Homepage section, through ``PUT /api/domains/:extid/homepage-config``
  (``allowed_cidrs`` / ``denied_cidrs``), and in the colonel domain configs
  editor. Signed-in members and the management pages are never restricted.
  Matching uses the request's resolved client address at full precision
  through the ``otto.ip_match`` verdict, so single-address entries work and
  the privacy-masked address is never consulted.
