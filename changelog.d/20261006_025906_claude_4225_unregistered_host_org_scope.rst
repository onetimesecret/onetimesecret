.. A new scriv changelog fragment.

Security
--------

- An authenticated request on a host that is neither a canonical host nor a
  subdomain of one, and whose custom-domain lookup found no record, gets no
  organization context. Such a host counted as having no domain scope, so a
  member confined to one custom domain could select any of their
  organizations there, ``O-Organization-ID`` included. Every organization is
  now withheld on it, for org-scoped members too. (#4225)
