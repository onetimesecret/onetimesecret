Fixed
-----

- The workspace chosen in the scope switcher is kept across a page reload
  and when opening a page by URL. The switcher records the choice in the
  server session, so the page is rendered for the selected workspace. (#4565)

- The scope switcher stays available after selecting a workspace you do
  not own, as long as you own another one. (#4565)

- A workspace chosen just before a page reload is kept when the reload
  overtakes the request that records it. (#4565)

- The scope switcher shows the settings gear only for workspaces whose
  settings you can open (owner or admin). (#4565)

Changed
-------

- Archived organizations are no longer resolved from the
  ``O-Organization-ID`` header, a stored session selection or the
  request's custom domain; the request falls back to the default
  organization. (#4565)

Removed
-------

- The per-session organization cache in ``OrganizationLoader``. It never
  matched across requests, so the organization was already resolved on
  every request. (#4565)
