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
  the bottom of the page that keeps clear of the workspace footer. Deleting
  the configuration moved to a Careful Consideration Zone at the end of
  the page, as on the domain page. Leaving the page with unsaved changes
  asks first.
