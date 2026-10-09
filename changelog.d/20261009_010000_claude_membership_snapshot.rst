.. A new scriv changelog fragment.

Changed
-------

- A request reads a customer's organization memberships once. The
  organization resolved during authentication, the "Default" label and
  role in the bootstrap payload, the organizations list, and the active
  organization recorded at session commit all share that one read, so an
  authenticated page load makes fewer datastore calls. Nothing is kept
  between requests, and a membership or default-workspace change made
  during the request is seen by the rest of that request.
