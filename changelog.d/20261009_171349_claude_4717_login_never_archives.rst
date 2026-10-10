.. A new scriv changelog fragment.

Changed
-------

- Signing in through a custom domain's SSO joins the customer to the
  domain's organization and makes it their default workspace, as before.
  It no longer archives the personal workspace it replaced as the default:
  that workspace stays listed and can be switched to. Joining an
  organization and choosing a default are decisions the sign-in makes;
  retiring a workspace is left to an operator (#4717).
