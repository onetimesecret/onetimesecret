Security
--------

- An authenticated request on a host the deployment does not serve (not a
  canonical host, a subdomain of one, or a registered custom domain) gets no
  organization context. Such a host counted as having no domain scope, so a
  member confined to one custom domain could select any of their
  organizations there, ``O-Organization-ID`` included. Every organization is
  now withheld on it, for org-scoped members too. (#4225)
