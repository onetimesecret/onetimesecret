Fixed
-----

- Operations that act on a customer's own workspace no longer pick another
  member's default workspace because it was listed first. The organization a
  member joined carries its owner's default flag too; the SSO sign-in
  self-heal, the deferred federated-subscription claim, the pro-bono
  entitlement grant, checkout and billing-portal targeting, and the
  organization-creation quota now resolve the workspace the customer owns.
  The quota counts the organizations a customer owns rather than every
  membership. A checkout or portal request whose explicit default points at
  an organization the caller does not own is refused as before, never
  redirected to a different workspace. The admin customers list and customer
  detail page label whose plan they show and read billing from the
  organization the customer owns, never from one they merely joined.
