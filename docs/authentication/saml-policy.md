# SAML policy settings

This reference covers optional NameID and tenant callback-origin settings. For the IdP certificate and endpoint setup, see [per-domain SSO](per-domain-sso.md) and [per-install SSO](per-install-sso.md).

## NameID policy

The platform environment variable `SAML_NAME_ID_FORMAT` and tenant API field `name_id_format` accept:

- `urn:oasis:names:tc:SAML:2.0:nameid-format:persistent` (default)
- `urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress`
- `urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified`
- `urn:oasis:names:tc:SAML:2.0:nameid-format:transient` — platform only, and only with `SAML_UID_ATTRIBUTE` set; the tenant API rejects it (422 on `name_id_format`) because tenant records have no UID attribute and every sign-in through it would be refused as `saml_transient_name_id`. A platform that sets the transient format without `SAML_UID_ATTRIBUTE` is not usable: the provider is skipped at boot with a message naming both variables.
- `omit` — sends no NameIDPolicy element; the strategy receives `nil`.

This setting controls the outgoing request, not identity-stability checks. A transient response without a configured stable UID attribute remains refused. The platform can configure `SAML_UID_ATTRIBUTE`; this change does not introduce a tenant UID override. JSON `null`, empty strings, and unknown formats are rejected.

### Changing the NameID format

Every SAML identity is keyed on the NameID the IdP sent (the platform can key on `SAML_UID_ATTRIBUTE` instead; tenants cannot). Changing the format changes that key, so existing identities will not match after the switch — each user's next sign-in provisions or links a new identity instead of resuming the old one, and does so under the linking and JIT rules in force at that time. A tenant PATCH or PUT that changes the effective `name_id_format` of an existing SAML record is accepted; it is recorded in the audit log at WARN level as `domain_sso_name_id_format_changed` (with `was_enabled` and `identities_rekeyed: true`, never the formats themselves). A PUT that omits `name_id_format` restores persistent and counts as a change when the record had another format. Platform installs get no warning: `SAML_NAME_ID_FORMAT` is read at boot, so treat a change to it as an identity migration unless `SAML_UID_ATTRIBUTE` supplies the key.

## Tenant callback origins

An organization owner with the SSO entitlement can set `callback_origins` through the domain SSO API. It is an array of at most 16 exact HTTPS origins, for example:

```json
{
  "callback_origins": ["https://login.corp.example"],
  "name_id_format": "omit"
}
```

Send this body with `PATCH /api/domains/:domain_extid/sso` using the existing authenticated API and CSRF requirements. The example assumes a SAML configuration already exists.

The SSO URL's origin remains admitted. Additional origins apply only to POST requests on that tenant's resolved SAML callback route. They do not widen global Origin or CSP policy, and do not bypass signature, issuer, audience, transaction-binding, or replay checks. A custom IdP domain needs an exception only when its actual posting origin differs from the configured URL's origin and other existing allowances.

Use origins without a path, trailing slash, credentials, query, fragment, wildcard, or explicit default port. Non-default HTTPS ports are supported. Literal `Origin: null` is denied by default; no tenant setting can enable it. The operator-only exception below is separate from this allowlist. A missing Origin header is distinct and retains the installed middleware's existing behavior.

PATCH omission preserves either policy; `callback_origins: []` clears exceptions. PUT omission restores persistent NameID and an empty exception list. Switching away from SAML clears both policies. GET returns them, or names unreadable policy fields in `unreadable_fields`. Policies are stored with domain-bound authenticated encryption. These advanced fields are API-managed; the existing UI uses PATCH for SAML and preserves omitted policy values.

## Operator opt-in for literal `Origin: null`

Some IdP flows submit an opaque browser origin, serialized as the literal header `Origin: null`. To permit those callbacks, the deployment operator can explicitly set:

```sh
SAML_ALLOW_NULL_ORIGIN=true
```

Apply the environment setting to every application worker and restart them. Only the exact string `true` enables the exception. Unset or `false` denies it; malformed values (including `TRUE`, `1`, `yes`, and whitespace-padded values) also deny it. Remove the variable or set it to `false` to withdraw approval.

The exception applies only to **POST on the resolved, configured SAML callback route**:

- Platform SAML must be enabled and usable, and the public host must pass the existing boot-pinned platform ACS host checks.
- Native tenant SAML must resolve to an available, enabled SAML configuration on a verified custom domain, with usable runtime settings. The request must target that configuration's callback route.
- Missing, disabled, unreadable, or unusable configurations do not receive the exception. Lookup errors fail closed. Platform SAML fallback on custom domains remains prohibited.
- Sign-in initiation, metadata, logout, OAuth callbacks, ordinary routes, and non-POST methods receive no exception. Rack's existing safe-method handling remains unchanged.

This is an installation-wide operator decision for eligible SAML callbacks, **not** a tenant-controlled field or an addition to global Origin/CSP allowances. `callback_origins` continues to reject `null`. Do not put `null` in `SSO_FORM_ACTION_ORIGINS`.

An opaque origin does not identify the IdP: sandboxed or other opaque-origin documents can also send `null`. Enabling this option explicitly removes the Origin source check for the narrowly scoped callbacks above; it is not authentication. The POST only stages the untrusted assertion. Completion still requires the initiating session and pending AuthnRequest, a valid signed assertion, issuer/audience/recipient checks, and replay protection. See [SAML callback transport](saml-callback-transport.md).

A missing Origin header is not the literal `null` value and is unaffected by this option. Other unlisted origins remain denied.

## Certificate compatibility and recovery

Newly accepted and active SAML configurations require a certificate containing an RSA public key. EC and other public-key types are rejected, regardless of the algorithm that signed the certificate itself. Both certificate validity bounds are checked at use time.

A legacy configuration with an unsupported key can still be disabled. While disabled, unchanged certificate data may be preserved during edits. Replace the certificate with a supported, currently valid certificate before re-enabling. Full PUT replacement and DELETE remain recovery options.
