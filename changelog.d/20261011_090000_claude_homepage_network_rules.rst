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
  the privacy-masked address is never consulted. Secret links still open
  from any network, so staff can create from a known network while
  recipients open links from anywhere. In incoming mode the rules decide
  who sees the form on the homepage only: the ``/incoming`` page and the
  incoming API are not restricted by network.

- New ``homepage_network_rules`` entitlement (Identity Plus in the example
  catalog). Changing either list requires it; the homepage experience
  selector does not. After a downgrade, stored rules stay enforced and are
  shown read-only. Operators with billing enabled must add the entitlement
  to the relevant plans in ``etc/billing.yaml`` and push the catalog;
  installs with billing disabled get it automatically.

- New platform flag ``ORGS_HOMEPAGE_NETWORK_RULES_UI_ENABLED``
  (``features.organizations.homepage_network_rules_ui_enabled``), off by
  default. Editing network rules needs it on, in addition to the
  entitlement, on every install. With it off the workspace editor is hidden
  and ``PUT /api/domains/:extid/homepage-config`` refuses a changed list (a
  422 form error of type ``forbidden`` on that field). A list sent back
  unchanged is accepted, so read-modify-write clients keep working. Turning
  it off stops edits only: rules already stored stay enforced
  and are shown read-only, so the switch never opens a homepage a tenant
  restricted. The colonel domain configs editor is not gated by it.
