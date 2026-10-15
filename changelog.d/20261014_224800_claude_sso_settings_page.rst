.. A new scriv changelog fragment.

Changed
-------

- A custom domain's SSO configuration is now its own settings page,
  ``/org/<org>/domains/<domain>/signin/sso``, reached from the domain's
  sign-in settings, the domains table and the organization settings. The
  dialog it replaces is gone; the old ``?modal=sso`` link on the sign-in
  settings page redirects to the new page. The form is laid out as a page:
  the setup steps are collapsed under a one-line summary, the identity
  provider details sit in one flat section, the optional provider settings
  check is folded under the saved-configuration check, and the check
  result scrolls into view when it arrives. The actions stay in a bar at
  the bottom of the page that keeps clear of the workspace footer and, on a
  phone, of the bottom navigation. Deleting the configuration moved to a
  Careful Consideration Zone at the end of the page, as on the domain
  page. Leaving the page with unsaved changes asks first.

Fixed
-----

- Switching to another domain from the header's domain switcher while a
  domain's brand, sign-up, incoming secrets, email or SSO settings have
  unsaved changes now asks first, as leaving the page does. Cancelling
  keeps the edits and leaves the switcher on the current domain.
- Switching organizations from the header's organization switcher while
  the page has unsaved changes no longer switches the organization before
  the page asks. Cancelling keeps the edits and leaves the organization,
  its switcher and the domain list as they were; the switch now lands
  together with the navigation it goes with.
- The domain settings pages' header is now as wide as the content below
  it instead of overhanging it on both sides. On a phone the header's
  back link shows only its arrow, so the domain name has room.
- A date or time that ends in an abbreviation period (``11:44 p.m.``, or
  Hungarian and Korean dates) no longer ends the SSO last sign-in
  sentence or the certificate expiry notice with a doubled period.
