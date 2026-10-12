# SSO: Entra claim smoke test (operator-approved)

**Symptom:** an Entra ID sign-in ends on `/signin?auth_error=missing_email`
(or `invalid_email`), or an operator wants to know, before rollout, what
the tenant's ID tokens carry for each account type that will sign in.

**What this runbook settles:** which claims the tenant's tokens actually
contain for the account types in scope, recorded as sanitized presence and
type, never values. It does not settle whether a user has a mailbox: a
missing `email` claim means the token did not carry one, nothing more
(Microsoft's [ID token claims reference](https://learn.microsoft.com/en-us/entra/identity-platform/id-token-claims-reference#payload-claims)).

## What is already proven without a live tenant

The repository's own test suite drives the mounted Entra route through the
real `omniauth-entra-id` strategy with synthetic ID tokens shaped like
Microsoft's documented v2.0 payloads
([entra_native_claims_spec.rb](../../apps/web/auth/spec/integration/full/entra_native_claims_spec.rb),
run with `tests/lanes/run full-sqlite --only <that path>`). It establishes:

- A token with an `email` claim is mapped into `info.email`, the account is
  created and the user is signed in. A padded claim is trimmed first.
- A token without an `email` claim yields a nil `info.email`, is refused
  with `missing_email`, and creates no account or identity. An email-shaped
  `preferred_username` or guest UPN is not substituted.
- The strategy's only egress is the token endpoint. `raw_info` is the
  decoded token; no Microsoft Graph or UserInfo call adds claims, and no
  `mail` field ever appears. A `raw_info['mail']` fallback (merged to
  `develop` in #3965 for nonstandard providers) therefore cannot apply to a
  native Entra token.

What the suite cannot establish is which shape a particular tenant emits
for a particular account type. That needs the live test below.

## Preconditions

- Written approval from the operator of the OTS install and from the
  tenant's Entra administrator. Production tenants: agree a window and the
  accounts to use.
- One test account per account type in scope. Typical set: a managed
  member with an Exchange mailbox, a managed member without one, a B2B
  guest (`#EXT#` UPN). Add a consumer (MSA) account only if the app
  registration allows it.
- Access to the OTS logs for the window (`omniauth_*` auth events).
- The gem and OTS versions: `bundle list | grep omniauth-entra-id` in the
  app container, and the OTS release.

## Procedure

1. **Sign in with each test account** through the OTS SSO button on the
   intended surface (the platform host or the tenant's custom domain). Use
   a fresh browser session per account. Record the outcome per account:
   signed in, `missing_email`, `invalid_email`, `domain_not_allowed`, or
   `sso_failed`.
2. **Read the OTS log line for each outcome.** A first-time refusal logs
   `omniauth_missing_email` (`provider: entra`) or
   `omniauth_invalid_email`; a tenant allowlist refusal logs
   `omniauth_tenant_domain_rejected` with `reason`. Returning identities do
   not need the claim on the platform surface; see
   [the error code table](../authentication/per-install-sso.md#email-claim-and-domain-errors).
3. **Record claim presence and type** for each refused account type. The
   Entra administrator can decode a token for the same app registration
   with Microsoft's own viewer at `https://jwt.ms`, which decodes in the
   browser and sends the token nowhere. This needs `https://jwt.ms` as a
   redirect URI and ID tokens enabled on the registration (or a throwaway
   test registration with the same **Token configuration**); remove the
   redirect URI afterwards. From the decoded token, note only whether each
   of these claims is present and what type it is:

   | Claim | Present | Type |
   |-------|---------|------|
   | `email` | | |
   | `preferred_username` | | |
   | `upn` | | |
   | `xms_edov` | | |
   | `name` | | |
   | `oid` | | |
   | `tid` | | |
   | `idp` | | |
   | `ver` | | |
   | `mail` (expected absent) | | |

4. **If `email` is absent for a managed member**, the Entra administrator
   can add the `email` optional claim under **Token configuration** and
   confirm the user has a primary address in the directory. Microsoft
   documents that the claim is still not guaranteed. Repeat steps 1 to 3
   for that account. Do not work around a missing claim with `upn`,
   `preferred_username`, a fabricated address, trusted linking, or by
   removing a tenant allowlist.

## What to report, and what never to post

Report, per account type: surface (platform or tenant host), flow
(first sign-in, returning, Connect), outcome and error code, the
`omniauth_*` event name, the claim table above, the app registration's
optional-claim configuration, and the gem and OTS versions.

Never post an ID token, access token, the OmniAuth auth hash, claim
values, or screenshots that show identifiers. Issue reports go in
[#3499](https://github.com/onetimesecret/onetimesecret/issues/3499) using
this format.

## Interpreting the result

- `email` absent on a first sign-in: expected `missing_email`. First-time
  provisioning without a claim is the
  [proposed Phase 2 work](../planning/2026-1009-sso-email-less-accounts.md);
  an existing account holder may use the
  [conditional Connect path](../authentication/per-install-sso.md#existing-account-with-a-missing-email-claim).
- `email` present but refused: check `invalid_email` (shape) against
  `domain_not_allowed` (policy) before touching the IdP.
- `xms_edov` is domain-owner verification, not mailbox control. Its
  presence does not change the outcome today; see
  [RISK-2026-10-10-02](../security/active-risk-register.md).
