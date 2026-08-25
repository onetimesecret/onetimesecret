.. A new scriv changelog fragment.

Fixed
-----

- Guest-created secrets on branded custom domains now use the domain owner
  organization's lifetime limit (normally 14 or 30 days). The 7-day anonymous
  default remains specific to guest creation on canonical hosts.

Documentation
-------------

- Documented the canonical-host and custom-domain guest TTL boundaries in the
  API and TTL-policy references.

AI Assistance
-------------

- AI assistance was used to investigate the regression, implement the policy
  fix, and add regression coverage.
