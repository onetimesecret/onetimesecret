.. A new scriv changelog fragment.

Security
--------

- A member whose organization membership is limited to one custom domain is
  now held to that scope whichever way a request selects an organization: the
  ``O-Organization-ID`` header the web app sends, the session's remembered
  organization and the fallbacks included. Behind a proxy that rewrites
  ``Host`` to the origin target the scope is now checked too; it was
  previously not checked there at all. When it withholds every organization
  the request gets none, instead of the member's first one. (#4225, #4623)

Changed
-------

- On a canonical host, organization loading no longer reads the custom-domain
  index, so an outage of that index no longer affects it there. On a custom
  domain whose record could not be read, the request fails; behind a proxy
  that rewrites ``Host``, the failed read used to leave nothing to check and
  an organization was loaded without the scope check. (#4623)
