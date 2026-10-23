# SAML IdP metadata consumption

Status: Draft — 2026-10-22. Baseline: `main` at `d136e3d74c`. Gems: omniauth-saml 2.2.5, ruby-saml 1.18.1 (pinned). All paths are repo-relative; gem paths are inside the installed gem.

Requested by a Team Plus customer (a large university) running Entra ID. They want the tenant SAML form to take an IdP metadata URL instead of three pasted values, and they want sign-in to survive Entra's signing-certificate rotation.

Two deliverables, shipped separately:

1. **Fetch and prefill** (Phase 1). A metadata URL field and a "Fetch" action that fills the IdP trio for the admin to review and save. No new trust surface: nothing is stored or applied without the admin saving the form through the existing PUT/PATCH path.
2. **Multi-certificate trust anchor and scheduled refresh** (Phase 2). The stored trust anchor becomes a set of signing certificates, and a daily job re-reads the metadata so a rotated certificate is trusted before the IdP starts using it. This is the part that prevents the silent break at rotation, and the part that needs the design decisions in section 6.

One finding changes the Phase 1 scope from the original sketch: Entra's metadata routinely lists more than one signing certificate, so the prefill has to show a certificate picker on day one (section 3).

## 1. What the metadata document gives us

ruby-saml ships `OneLogin::RubySaml::IdpMetadataParser`. `parse_to_hash(xml, options)` (idp_metadata_parser.rb:158) returns, per `IDPSSODescriptor`:

| Key | Value | Maps to |
| --- | --- | --- |
| `idp_entity_id` | `EntityDescriptor/@entityID` | `idp_entity_id` (stored byte-for-byte; the issuer half of the identity key) |
| `idp_sso_service_url` | `SingleSignOnService/@Location` for the first binding in `options[:sso_binding]` | `idp_sso_service_url` |
| `idp_cert` | the one signing certificate, **bare base64** (the `X509Certificate` element text, no PEM armour), or `nil` when there is more than one | `idp_cert`, after PEM wrapping |
| `idp_cert_multi` | `{ signing: [base64, ...], encryption: [...] }`, always populated when any certificate exists | Phase 2 trust set |
| `name_identifier_format` | first `NameIDFormat` matching `options[:name_id_format]` | advisory only (see 4.4) |
| `valid_until`, `cache_duration` | root attributes | refresh pacing hints; Entra publishes neither |

Three details that matter for the implementation:

- The parser's `merge_certificates_into` (idp_metadata_parser.rb:406) sets `idp_cert` only when exactly one signing certificate is present. With two or more, `idp_cert` is `nil` and the certificates are only in `idp_cert_multi[:signing]`.
- `KeyDescriptor` elements without a `use` attribute are counted as both signing and encryption (`certificates`, :350). Entra marks every key `use="signing"`.
- `parse_remote*` (idp_metadata_parser.rb:67) fetches with a bare `Net::HTTP` and no egress guard. It must never be called; we fetch with our own fetcher and hand the body to `parse_to_hash`.

Binding selection: `RequestBoundSAML#request_phase` redirects to `Authrequest#create` (request_bound_saml.rb:287), i.e. HTTP-Redirect. Pass `sso_binding: ['urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect', 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST']` so the Redirect location is preferred and a POST-only IdP still yields a URL.

## 2. What Entra actually publishes

Fetched 2026-10-22 from `https://login.microsoftonline.com/common/federationmetadata/2007-06/federationmetadata.xml` (public, tenant-neutral; a tenant-specific URL has the same shape):

| Property | Observed |
| --- | --- |
| Size | 24,606 bytes, `text/xml; charset=utf-8` |
| Root `entityID` | `https://sts.windows.net/{tenantid}/` |
| `IDPSSODescriptor` | one, with **four** `KeyDescriptor use="signing"` entries |
| `SingleSignOnService` | HTTP-Redirect and HTTP-POST, same Location (`.../saml2`) |
| `validUntil` / `cacheDuration` | absent |
| Document signature | present (enveloped `ds:Signature` on the root) |
| Other descriptors | two WS-Federation `RoleDescriptor` entries (ignored by the parser) |

The tenant-level document lists the tenant's global signing keys. For an Enterprise Application with its own SAML signing certificate (the normal Entra setup), the admin must use the **App Federation Metadata Url** that Entra shows on the app's SAML page: the same path with `?appid=<application-id>`. That document carries the app's certificate(s): one outside a rollover, two while a new certificate has been added but not yet activated. Verify this against the customer's app metadata before relying on the count; it could not be checked here without an application id.

Consequence: the `idp_cert` key from the parser cannot be relied on for Entra. The prefill must work from `idp_cert_multi[:signing]`.

## 3. The finding that changes Phase 1

The original sketch assumed the parser returns the trio and the form fills three fields. For Entra it returns the EntityID, the SSO URL and a **list** of signing certificates, with no marker for which one is active. SAML metadata has no "active" flag; Entra's portal shows it, the XML does not.

Phase 1 therefore needs a certificate picker when the list has more than one entry: subject, validity window and SHA-256 fingerprint per certificate, so the admin can match the thumbprint Entra's portal marks as active. With exactly one certificate the picker collapses to a prefilled textarea. Storing the whole list stays in Phase 2 because it changes the trust-anchor shape (section 5.1).

## 4. Phase 1: fetch and prefill

### 4.1 Endpoint

`POST /api/domains/:extid/sso/metadata` → `DomainsAPI::Logic::SsoConfig::FetchIdpMetadata`, beside `TestConnection` in `apps/api/domains/routes.txt:32`. Same guards as `TestConnection#raise_concerns` (session, domain ownership, organization entitlement), plus `reject_saml_disabled!` from `SamlFields` (SAML off on the install means nothing fetched can be saved).

Request body: `{ "metadata_url": "https://..." }`.

Response on success:

```json
{
  "success": true,
  "metadata_url": "https://login.microsoftonline.com/<tenant>/federationmetadata/2007-06/federationmetadata.xml?appid=<app>",
  "idp_entity_id": "https://sts.windows.net/<tenant>/",
  "idp_sso_service_url": "https://login.microsoftonline.com/<tenant>/saml2",
  "signing_certificates": [
    {
      "pem": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----",
      "subject": "CN=Microsoft Azure Federated SSO Certificate",
      "not_before": "2026-01-10T00:00:00Z",
      "not_after": "2029-01-10T00:00:00Z",
      "fingerprint_sha256": "AB:CD:...",
      "problem": null
    }
  ],
  "name_id_formats": ["urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"],
  "problems": []
}
```

- `pem` is the parser's base64 wrapped into one PEM block (`OneLogin::RubySaml::Utils.format_cert`, utils.rb:101, does exactly this). The form posts it back through the unchanged PUT/PATCH path, so `Saml.cert_problem` (saml.rb:430) is still the only acceptance gate.
- `problem` per certificate is `Saml.cert_problem(pem)` evaluated server-side (expired, not yet valid, non-RSA key), so the picker can grey out a certificate the save would refuse.
- `problems` carries record-level issues found with the same validators the save uses: `Saml.entity_id_problem` and `Saml.sso_url_problem`. An EntityID with surrounding whitespace, or an SSO URL with a fragment, is reported here rather than discovered at save time.
- Failure responses reuse the `discovery_check.rb` error vocabulary (`invalid_issuer` renamed `invalid_metadata_url`, `blocked_target`, `timeout`, `ssl_error`, `connection_failed`, `http_error`, `discovery_too_large` → `metadata_too_large`, plus `invalid_metadata` for a body the parser rejects). The `blocked_target` message stays generic: `Guard::Blocked` carries the resolved IP and must not be echoed (discovery_check.rb:140).

The endpoint never writes. The admin reviews the filled fields and saves; `PutSsoConfig` / `PatchSsoConfig` validate the trio exactly as they do for pasted values.

### 4.2 Fetching

Reuse `Onetime::SsoProvider::DiscoveryFetcher` (discovery_fetcher.rb) as is: HTTPS only, host resolved once through `Onetime::Http::Guard` and every dial pinned to a validated IP, explicit nil proxy, `VERIFY_PEER`, no redirects, total deadline, body cap on declared length and on the stream. Two parameters change:

- `max_bytes`: the default is 256 KiB (`DEFAULT_MAX_BYTES`), ten times the observed Entra document, so the default is fine. Keep the constructor argument rather than subclassing.
- `Accept`: the fetcher hard-codes `application/json` (discovery_fetcher.rb `perform`). Add an `accept:` constructor option defaulting to the current value, and pass `application/samlmetadata+xml, application/xml, text/xml` here. Do not gate on the response `Content-Type`: Entra answers `text/xml`, other IdPs answer `application/xml` or `application/samlmetadata+xml`, and some answer `application/octet-stream`. The parser is the gate.

Query strings must be accepted (`?appid=`); the fetcher already forwards `uri.request_uri`.

### 4.3 Parsing

`IdpMetadataParser.new.parse_to_hash(body, sso_binding: [...])` wrapped so that `ArgumentError` ("idp_metadata must contain an IDPSSODescriptor element") and `REXML::ParseException` both map to `invalid_metadata`.

The parser builds a `REXML::Document` directly (idp_metadata_parser.rb:177), not through ruby-saml's `safe_load_xml`. REXML 3.4.4 (installed) does not fetch external entities and bounds internal expansion (`REXML::Security.entity_expansion_limit` 10000, `entity_expansion_text_limit` 10240). The body cap bounds input size. Add two fixtures to the spec: a `DOCTYPE` with an internal entity bomb (must raise or produce no usable trio, never hang) and a document with an external entity reference (must not touch the network: the test asserts no `Net::HTTP` call).

A document with several `EntityDescriptor` elements (a federation aggregate) is refused with `invalid_metadata` and a message saying so; `parse_to_array` could return them all, but picking an IdP out of an aggregate is not a Phase 1 feature.

### 4.4 What is deliberately not prefilled

- `name_id_format`. The parser reports what the IdP advertises; the stored policy stays the admin's choice (`PERSISTENT_NAME_ID_FORMAT` default, transient refused at save, `SamlFields#validate_saml_policy!`). The advertised formats are returned for display beside the existing selector, nothing more.
- `callback_origins`, `allowed_domains`, `display_name`: unrelated to IdP metadata.
- Anything from the `encryption` certificate list. We do not request encrypted assertions (`want_assertions_encrypted: false`, saml.rb `SECURITY`), so an encryption key has no use and must not be offered as a signing certificate.

### 4.5 Storing the metadata URL

New record field `idp_metadata_url` on `CustomDomain::SsoConfig`, declared as `encrypted_field ... aad_fields: [:domain_id]` beside the trio (sso_config.rb:177). It is not secret; it is declared this way for the same integrity reason the trio is (sso_config.rb:163), because in Phase 2 it becomes the thing the refresh job trusts. Declaring it that way now avoids a field migration later.

- Accepted by PUT and PATCH for `provider_type: saml`, optional, cleared for other provider types (`SamlFields#provider_attributes`).
- Validated with `Saml.sso_url_problem` (https, plain host, no fragment) plus `SsrfProtection#valid_issuer_host?` (the server does fetch this URL, unlike the SSO URL; see the `NO SSRF host check` note in saml_fields.rb for why the SSO URL is exempt and this one is not).
- Served by `serialize_sso_config` in plaintext like the trio; `unreadable_fields` covers it.
- Logged by `ChangeLogger` as `changed: true` without the value (add to `SENSITIVE_FIELDS`, change_logger.rb:38, for the same reason the trio is there).
- Not consulted by the login path. `build_saml_options` (sso_config.rb:1004) stays trio-only in Phase 1.

### 4.6 Form

`DomainSsoConfigForm.vue`, inside the `v-if="isSaml"` block (line ~1479): a metadata URL input and a "Fetch from metadata" button above the trio. On success the composable (`useSsoConfig.ts`) writes `idp_entity_id` and `idp_sso_service_url` into `formState` through `updateField`, so `hasUnsavedChanges` and the unchecked-credentials warning behave as for typed input. The certificate goes into `idp_cert` directly when the list has one entry, otherwise a picker (radio list with subject, window, fingerprint, and the server's `problem`) sets it on selection.

The button is advisory; the primary action stays "Save and check". `TestConnection` for SAML is local (test_connection.rb:236) and remains the way the admin confirms the filled trio before saving.

Service: `SsoService.fetchIdpMetadataForDomain(extid, { metadata_url })` in `sso.service.ts`, with a zod response schema in `src/schemas/api/domains/responses/sso-config.ts`. Strings in `locales/content/en/workspace-organizations.json` under `web.organizations.sso.*`.

### 4.7 Rate limit

Per customer, through `Onetime::Security::PerCustomerRateLimit` with a new policy module next to `SsoDiagnosticsRateLimiter`. The endpoint makes one outbound request per call to a customer-chosen host, so the reason to bound it is egress volume from a leaked owner session, not oracle behaviour. 30 per hour is enough for an admin iterating on a URL. Charged after the ownership and entitlement guards, like diagnostics (run_diagnostics.rb:183).

### 4.8 Tests

- `spec/unit/onetime/sso_provider/idp_metadata_spec.rb` (new module `Onetime::SsoProvider::IdpMetadata` that wraps the parser and PEM wrapping): one-cert, four-cert (the Entra common document, recorded as a fixture), no `IDPSSODescriptor`, aggregate, entity bomb, external entity, bare base64 to PEM round-trip through `Saml.cert_problem`.
- `apps/api/domains/spec/logic/sso_config/fetch_idp_metadata_spec.rb`: guard order, rate limit, each fetcher status mapping, no write to the record.
- `DomainSsoConfigForm.spec.ts`: picker shown for two certificates, textarea filled for one, `problem` disables selection.

Run through `tests/lanes/run --only <path>` while iterating, then the lane before pushing.

### 4.9 Out of Phase 1

No storage of more than one certificate, no scheduled fetch, no metadata signature verification, no change to the verifier or to any invariant comment in `saml.rb` or `request_bound_saml.rb`. The customer's cert rotation still requires an admin to press "Fetch" and save; the difference is that pressing it is the whole job.

## 5. Phase 2: multi-certificate trust anchor and scheduled refresh

### 5.1 Trust anchor becomes a set

Today the anchor is one PEM block: `cert_problem` refuses anything else (saml.rb:396), `SamlFields::FORBIDDEN_PARAMS` refuses `idp_cert_multi` at the API (saml_fields.rb:79), `strategy_options_for` sets only `idp_cert` (saml.rb:306). Rotation needs two certificates trusted at once: the current one and its successor, during the window between Entra publishing the new certificate and activating it.

ruby-saml supports this, and its multi-certificate verification is stricter than the single path, which matters for the invariant comments:

- Single path (`Response#validate_signature`, response.rb:906-920): matches a response-embedded certificate to the pinned one by fingerprint (`idp_cert_fingerprint_algorithm`, pinned to SHA-256 in `Saml.hardened_options`), then verifies with the **embedded** certificate.
- Multi path (response.rb:921-940, `XMLSecurity#validate_document_with_cert`, xml_security.rb:287): when `idp_cert_multi[:signing]` is non-empty, `idp_cert` and the fingerprint algorithm are ignored. For each pinned certificate: an embedded certificate must be **byte-equal by PEM** to it, and the signature is verified with the **pinned** certificate. One success restores the error list; `check_idp_cert_expiration` then refuses an expired match.

So the move is: `strategy_options_for` emits `idp_cert_multi: { signing: [pem, ...] }` and no `idp_cert` when the stored set has more than one entry, or always emits the multi form (simpler, one verifier path to reason about; recommended). Every comment that describes the fingerprint match-then-embedded verification becomes historical: saml.rb:41-46 and :221-230, request_bound_saml.rb:163-167. Rewrite them to describe the multi path, and re-run `registry_spec` and `request_bound_saml_spec`.

Storage: keep `idp_cert` as the **primary** certificate (unchanged semantics for every existing reader: serializer `cert_expires_at`, diagnostics `certificate` check, `idp_cert_not_after`) and add `idp_cert_successors_json`, an encrypted, domain-bound JSON array of additional PEM blocks (each individually passing `cert_problem` with `allow_expired: true` on the model and `false` on the API). Bounded to a small count (4 covers Entra's tenant document). `#saml_trio` grows a fourth key; `build_saml_options` passes the full list.

API: `idp_cert_multi` stays forbidden as a request parameter (it is ruby-saml's spelling, and accepting it would re-open the fingerprint-only shapes); the API field is `idp_cert_successors` (array of PEM). The form shows the primary textarea plus a read-only list of successors with their windows and a remove action.

Model invariant: `saml_validation_errors` validates each successor structurally, same `allow_expired: true` rule as the primary (an expired successor must not make the record uneditable).

### 5.2 What the refresh may change

The refresh job reads the stored `idp_metadata_url`, fetches and parses as in Phase 1, then:

1. **Refuses** to apply anything when the metadata `entityID` differs from the stored `idp_entity_id`. A different EntityID is a different IdP; that is an admin decision, surfaced as a failed refresh outcome, never applied.
2. **Never changes** `idp_sso_service_url`. A changed URL is reported in the outcome, not applied. The URL is where the browser is sent to enter credentials; a metadata-driven change of it is the exact move a compromised metadata host would make.
3. **Adds** signing certificates from the metadata that are not yet stored, each passing `cert_problem` (window and key type), as successors.
4. **Promotes** a successor to primary when the primary has expired and a successor is within its window. Promotion happens on the job, not at login: the login path has no writer.
5. **Removes** stored certificates that the metadata no longer lists only after they have expired. Entra removes a retired certificate from metadata when it is deactivated, which can happen before it expires; keeping it until expiry means a response signed with the old certificate during the switch-over minute still verifies, at the cost of trusting a deactivated key for its remaining lifetime. With Entra's three-year certificates and the customer rolling early, that remaining lifetime can be long. Decision needed: remove on absence (tighter) or on expiry (safer against a race). Recommended: remove on absence, after the metadata has been read successfully twice without it, so a transient bad read cannot shrink the trust set.

Every applied change goes through the model's guarded write (`Onetime::Models::Features::GuardedConfigWrites`, the WATCH-and-retry path PUT/PATCH use via `guarded_config_write`, apps/api/domains/logic/base.rb:56), so a concurrent admin edit wins and the job retries on its next run.

### 5.3 Trust on refresh

With Phase 2, whoever controls the metadata URL controls which signatures the tenant accepts. Two tiers:

- **Auto-apply allowlist**: hosts whose metadata is served by the IdP vendor over TLS and where the trust is already placed in the vendor: `login.microsoftonline.com` and the sovereign-cloud hosts the Entra provider recognises (`lib/onetime/sso_provider/entra.rb`, `docs/specs/sso/entra-sovereign-clouds-research.md`). The fetch is TLS-verified and IP-pinned, so this is the same trust the OIDC/Entra path places in the discovery document.
- **Everything else**: fetch, diff, and report. The diff (new certificate fingerprints, missing fingerprints, changed URL, changed EntityID) is shown in the settings page with an "Apply" action that goes through the normal PATCH, logged by `ChangeLogger` with the admin as actor. No automatic write.

Metadata signature verification (Entra signs the document; `metadata_signed` is an SP-side setting, and ruby-saml has no IdP-metadata signature verifier) is not part of Phase 2. The TLS pin to a vendor host is the trust basis; the allowlist is what keeps that argument honest.

### 5.4 Scheduling

`Onetime::Jobs::Scheduled::SsoMetadataRefreshJob < ScheduledJob` in `lib/onetime/jobs/scheduled/`, registered like `DomainRefreshJob` (`every(scheduler, interval, first_in: '5m', overlap: false)`), config under `jobs.sso_metadata_refresh` (`enabled`, `check_interval` default `24h`, `batch_size`). Single-instance assumption as documented in domain_refresh_job.rb:40-60 (one `bin/ots scheduler` per datastore); two schedulers would double the fetches but, with WATCH writes, not corrupt the record.

Daily is enough: Entra publishes a new certificate well before activating it (the admin chooses the activation date, usually days to weeks out), and the document carries no `cacheDuration` to pace against.

Scope per run: every enabled `saml` record with a non-blank `idp_metadata_url`. `SsoConfig.all` exists (sso_config.rb:898); add an index or a scan filter if the count makes a full walk expensive (today it does not).

### 5.5 Failure mode

- **Last-known-good**: a failed fetch or parse never alters the stored set. Sign-in continues on what is stored.
- **Outcome record**: a runtime sibling of `CustomDomain::SsoSigninOutcome` (sso_signin_outcome.rb), `SsoMetadataRefreshOutcome`: `last_at`, `last_result`, `last_code` (the fetcher status or `entity_id_mismatch`, `sso_url_changed`, `no_signing_certificates`), `last_applied_at`, fingerprints added and removed on the last applied run, bound to `signin_outcome_generation` so a replaced record does not inherit history, 90-day TTL, best-effort writes. Separate from `SsoConfig` for the reason that file states: the owner-written, audited record's `updated` stamp must not move on a job tick that changed nothing.
- **Diagnostics**: a new `metadata` check in `RunDiagnostics` for saml records (run_diagnostics.rb:305 lists `%w[certificate]` today): `passed` when the last refresh succeeded within two intervals, `failed` with the last code otherwise, `skipped` when no metadata URL is stored. The `certificate` check gains the successor list, so "primary expires in 12 days, successor valid from today" reads as healthy.
- **Warning**: the form's 30-day notice (`CERT_EXPIRY_NOTICE_DAYS`, DomainSsoConfigForm.vue:373) stays, but becomes conditional: with a stored metadata URL and a successor already trusted, the notice says rotation is covered; with a URL and no successor it says the metadata has not published one yet; with a failing refresh it points at the `metadata` check. The runbook (`docs/runbooks/sso-credential-health.md`, "SAML certificate expiry") gains the job and the outcome record.
- **Audit**: `ConfigChangeLogger` requires a `Customer` actor (config_change_logger.rb:40-48). A job has none. Add a system-actor variant that logs `actor_id: 'system:sso_metadata_refresh'` with the same event shape, so an applied rotation appears in the organization's trail. Decision needed on whether the operator trail should see it too.

## 6. Decisions needed

1. **Phase 1 scope**: ship the picker (section 3) rather than "prefill the first certificate". Recommended: picker. Prefilling an inactive certificate is a silent sign-in break, the thing the customer asked us to remove.
2. **Successor removal rule** (5.2 item 5): on absence after two consecutive reads, or on expiry. Recommended: absence after two reads.
3. **Auto-apply allowlist** (5.3): Microsoft hosts only at launch, or Microsoft plus Google (`accounts.google.com`) and Okta tenant hosts (`*.okta.com`), which also serve metadata over vendor TLS. Recommended: Microsoft only; add vendors as customers ask, each with the same TLS-pin argument written down.
4. **Audit actor for job-applied changes** (5.5): organization trail only, or both trails.
5. **Ticketing**: Phase 1 as one PR against the customer request; Phase 2 as its own issue (model change, verifier change, job, diagnostics, runbook), with the `saml.rb` / `request_bound_saml.rb` invariant rewrite called out as a review item.

## 7. Files touched

Phase 1:

- `lib/onetime/sso_provider/discovery_fetcher.rb` (accept header option)
- `lib/onetime/sso_provider/idp_metadata.rb` (new: parse, PEM-wrap, per-certificate report)
- `apps/api/domains/logic/sso_config/fetch_idp_metadata.rb` (new), `routes.txt`, `logic.rb`
- `lib/onetime/security/sso_metadata_fetch_rate_limiter.rb` (new policy on `PerCustomerRateLimit`)
- `lib/onetime/models/custom_domain/sso_config.rb` (`idp_metadata_url`), `saml_fields.rb`, `serializers.rb`, `change_logger.rb`, `put_sso_config.rb`, `patch_sso_config.rb`
- `src/services/sso.service.ts`, `src/schemas/api/domains/{requests,responses}/sso-config.ts`, `src/shared/composables/useSsoConfig.ts`, `DomainSsoConfigForm.vue`, `locales/content/en/workspace-organizations.json`
- specs listed in 4.8

Phase 2 adds:

- `lib/onetime/sso_provider/saml.rb` (`strategy_options_for` multi form, comment rewrite), `request_bound_saml.rb` (comment rewrite), `sso_config.rb` (successors field, `saml_trio`, `build_saml_options`, `saml_validation_errors`)
- `lib/onetime/jobs/scheduled/sso_metadata_refresh_job.rb`, `etc/defaults/config.defaults.yaml` (`jobs.sso_metadata_refresh`)
- `lib/onetime/models/custom_domain/sso_metadata_refresh_outcome.rb`, `run_diagnostics.rb` (`metadata` check), `config_change_logger.rb` (system actor)
- `docs/runbooks/sso-credential-health.md`, and a spec entry under `docs/specs/` once the behaviour ships
