Fixed
-----

- The workspace chosen in the scope switcher is kept across a page reload
  and when opening a page by URL. The switcher records the choice in the
  server session, so the page is rendered for the selected workspace. (#4565)

- The scope switcher stays available after selecting a workspace you do
  not own, as long as you own another one. (#4565)

Changed
-------

- Archived organizations are no longer resolved from the
  ``O-Organization-ID`` header or a stored session selection; the request
  falls back to the default organization. (#4565)

Removed
-------

- The per-session organization cache in ``OrganizationLoader``. It never
  matched across requests, so the organization was already resolved on
  every request. (#4565)
