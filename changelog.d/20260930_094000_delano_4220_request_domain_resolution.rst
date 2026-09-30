.. A new scriv changelog fragment.

Changed
-------

- A request now looks up its custom domain once. The host classification
  step records whether the domain was found, is not registered, or could
  not be read, and the sign-in and sign-up checks, SSO, session and
  auth-link code read that result instead of each querying the datastore
  again. If that lookup fails, the later steps of the same request treat
  it as failed and do not retry it. (#4220)
