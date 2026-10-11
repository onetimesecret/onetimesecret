.. A new scriv changelog fragment.

Security
--------

- Single sign-on on a custom domain now creates an account only for an
  address whose domain the organization has verified: the custom domain
  itself, a name below it, or another custom domain of the organization
  whose TXT ownership check has passed. Before this, a tenant's identity
  provider could create a verified account for any address that had no
  account yet, and the address owner's later password reset or magic link
  would then share that account with the tenant identity. The email-domain
  allowlist now selects among verified domains; an empty allowlist admits
  every verified domain. People who already signed in through a tenant
  identity keep signing in, and such sign-ins from an address outside the
  verified domains are logged as ``omniauth_tenant_email_domain_unverified``
  so operators can review those accounts. Organizations whose people use
  addresses at a domain other than their custom domain (for example
  ``@acme.example`` with the custom domain ``secrets.acme.example``) need to
  add that domain as a custom domain and complete its TXT check before new
  people can sign in; the domain does not have to point at Onetime Secret.
  (#4734)
