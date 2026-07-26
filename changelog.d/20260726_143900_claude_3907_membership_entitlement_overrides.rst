.. A new scriv changelog fragment.

Added
-----

- Membership-level entitlement overrides are now operable outside a console
  (#3907, closing D19 of the #3731 CLI-over-Operations epic).
  ``OrganizationMembership`` has carried ``grant_entitlement`` /
  ``revoke_entitlement`` / ``clear_entitlement_overrides`` all along, with no
  adapter reaching them. A single shared operation
  (``Onetime::Operations::Memberships::EntitlementOverride``) now backs two new
  symmetric surfaces: ``bin/ots memberships entitlement grant|revoke|clear|show``
  (dry-run by default in the op, ``--yes`` gated, ``--json`` capable) and the
  colonel endpoints
  ``POST /api/colonel/organizations/:org_id/members/:member_id/entitlements/:action``
  / ``DELETE …/members/:member_id/entitlements/overrides``. The operation emits
  exactly one ``membership.entitlement.*`` audit event per applied change;
  adapters never audit. Overrides survive role changes, org plan changes and
  re-materialization, and never expire (matching org-level semantics; expiry is
  #3905).
