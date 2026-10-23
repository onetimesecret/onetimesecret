# SAML IdP metadata consumption

Status: Draft, 2026-10-22, revised 2026-10-23. Baseline: `main` at `d136e3d74c`. Gems: omniauth-saml 2.2.5, ruby-saml 1.18.1 (pinned). All paths are repo-relative; gem paths are inside the installed gem and were re-read from the unpacked 1.18.1 source for this revision.

Requested by a Team Plus customer running Entra ID. Their words: "SAML IDP metadata consumption ability: this would let me set the metadata URL for my app in OTS, and you could pull the URIs and certs through it." They want the tenant SAML form to take an IdP metadata URL instead of three pasted values. The unstated second half is that sign-in should survive Entra's signing-certificate rotation, which is the reason SPs consume metadata at all.

Two deliverables, shipped separately:

1. **Fetch and prefill** (Phase 1). A metadata URL field and a "Fetch" action that fills the IdP trio for the admin to review and save. No new trust surface: nothing is stored or applied without the admin saving the form through the existing PUT/PATCH path. This is the customer's literal request.
2. **Multi-certificate trust anchor and scheduled refresh** (Phase 2). The stored trust anchor becomes a set of signing certificates, and a job re-reads the metadata so a rotated certificate is trusted before the IdP starts using it. This is the part that prevents the silent break at rotation, and the part that needs the design decisions in section 6.

Two findings shape the scope:

- Entra's metadata routinely lists more than one signing certificate, so the Phase 1 prefill has to show a certificate picker on day one (section 3).
- Microsoft's published guidance for ISVs is to poll the per-application metadata at least every 24 hours, add a newly discovered certificate as a secondary while it is still inactive, and promote it after the customer activates it (section 2). Phase 2 is that recommendation implemented against our verifier.

## 1. What the metadata document gives us

ruby-saml ships `OneLogin::RubySaml::IdpMetadataParser`. `parse_to_hash(xml, options)` (idp_metadata_parser.rb:158) returns, for the first `IDPSSODescriptor`:

| Key | Value | Maps to |
| --- | --- | --- |
| `idp_entity_id` | `EntityDescriptor/@entityID` | `idp_entity_id` (stored byte-for-byte; the issuer half of the identity key) |
| `idp_sso_service_url` | `SingleSignOnService/@Location` for the first binding in `options[:sso_binding]` that the document offers; `nil` when none of the listed bindings is present | `idp_sso_service_url` |
| `idp_cert` | **unreliable; never read it** (see below) | nothing |
| `idp_cert_fingerprint`, `idp_cert_fingerprint_algorithm` | emitted alongside `idp_cert` | nothing: dropped before anything leaves the parser wrapper. Fingerprint parameters are refused by `SamlFields::FORBIDDEN_PARAMS` and must stay refused |
| `idp_cert_multi` | `{ signing: [base64, ...], encryption: [base64, ...] }`, symbol keys, present whenever any certificate exists; each entry is the `X509Certificate` element text (bare base64, no PEM armour) | `idp_cert_multi[:signing]` is the only certificate source, for both phases |
| `name_identifier_format` | first `NameIDFormat` matching `options[:name_id_format]` | advisory only (see 4.4) |
| `valid_until`, `cache_duration` | root attributes | refresh pacing hints; Entra publishes neither |

Details that matter for the implementation (all verified in the 1.18.1 source):

- `merge_certificates_into` (idp_metadata_parser.rb:406) sets `idp_cert` in three cases: the document has keys for exactly one `use` and exactly one certificate under it; or it has one signing and one encryption certificate and they are the same bytes. In every other case `idp_cert` is `nil`. In the "one use, one cert" case, if that use is `encryption`, **`idp_cert` is the encryption certificate**. That is the trap: an encryption key offered as a signing anchor would make every sign-in fail at signature verification. Read `idp_cert_multi[:signing]` and nothing else.
- `certificates` (:350) classifies by XPath `KeyDescriptor[not(contains(@use,'encryption'))]` for signing and `KeyDescriptor[not(contains(@use,'signing'))]` for encryption, so a `KeyDescriptor` without a `use` attribute is counted as both. Entra marks every key `use="signing"`.
- `parse_to_hash` is `parse_to_array(...)[0]` (:159): a document with several `EntityDescriptor` elements (a federation aggregate) silently yields the first IdP. Aggregate detection is ours: call `parse_to_array` and refuse when it returns more than one element (section 4.3). The parser's `options[:entity_id]` can select one IdP out of an aggregate if that is ever wanted; it is not in scope.
- `parse_to_idp_metadata_array` (:177) builds `REXML::Document.new(idp_metadata)` directly, not through ruby-saml's hardened loader (section 4.3).
- `parse_remote*` (:67, :86, :104) fetch with a bare `Net::HTTP` (`get_idp_metadata`, :194) and no egress guard. They must never be called; we fetch with our own fetcher and hand the body to `parse_to_array`.

Binding selection: `RequestBoundSAML#request_phase` redirects to `Authrequest#create` (request_bound_saml.rb:287), i.e. HTTP-Redirect. Pass `sso_binding: ['urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect', 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST']` so the Redirect location is preferred and a POST-only IdP still yields a URL. With that list, a document offering neither binding (SOAP-only, or malformed) returns `nil` for the URL; the endpoint reports that as a record-level problem (`no_sso_url`), not as a parse failure.

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

The tenant-level document lists the tenant's global signing keys. For an Enterprise Application with its own SAML signing certificate (the normal Entra setup, three-year default lifetime, admin-selectable up to three years), the admin must use the **App Federation Metadata Url** that Entra shows on the app's SAML page: the same path with `?appid=<application-id>`. That document carries the application's certificates.

What it carries during rollover is documented by Microsoft, not just observed. The Entra tutorial on managing federation certificates tells ISVs to "download metadata on a regular cadence, add newly discovered certificates as a secondary signing certificate while the new key is still inactive, and then seamlessly promote it to primary after the customer activates it," and to "monitor metadata at least every 24 hours." So the per-app document lists an added-but-inactive certificate alongside the active one, and SAML metadata has no flag for which is active; Entra's portal shows that, the XML does not. Two more Entra behaviours from the same page bear on Phase 2:

- "If both an expired and an inactive valid certificate exist on the application, Microsoft Entra ID automatically utilizes the valid certificate." An admin who lets the active certificate expire gets signing switched to the inactive one without pressing anything. A trust set that already contains both survives this; a single pinned certificate does not.
- "Make certificate active" flips the statuses in the portal with no grace period. The response signed a second later uses the new key.

Still verify the certificate count against the customer's own `?appid=` URL before relying on it in support material; it could not be fetched here without an application id.

Consequence for Phase 1: the prefill works from `idp_cert_multi[:signing]`, which for the customer's app will have one entry outside a rollover and two inside one.

## 3. The finding that changes Phase 1

The original sketch assumed the parser returns the trio and the form fills three fields. For Entra it returns the EntityID, the SSO URL and a **list** of signing certificates with no marker for which one is active.

Phase 1 therefore needs a certificate picker when the list has more than one entry: subject, validity window and SHA-256 fingerprint per certificate, so the admin can match the thumbprint Entra's portal marks as active. Nothing is preselected when there is more than one; the newest by `not_before` is labelled as such but not chosen. With exactly one certificate the picker collapses to a prefilled textarea. Storing the whole list stays in Phase 2 because it changes the trust-anchor shape (section 5.1).

## 4. Phase 1: fetch and prefill

### 4.1 Endpoint

`POST /api/domains/:extid/sso/metadata` → `DomainsAPI::Logic::SsoConfig::FetchIdpMetadata`, beside `TestConnection` in `apps/api/domains/routes.txt:32`. Same guards as `TestConnection#raise_concerns` (session, domain ownership, organization entitlement), plus `reject_saml_disabled!` from `SamlFields` (saml_fields.rb:211; SAML off on the install means nothing fetched can be saved).

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
- `problem` per certificate is `Saml.cert_problem(pem)` evaluated server-side (expired, not yet valid, non-RSA key), so the picker can grey out a certificate the save would refuse. A certificate the server cannot parse at all is listed with `problem: "unparseable"` and no `pem`, rather than dropped, so the count the admin sees matches the count in Entra's portal.
- `problems` carries record-level issues found with the same validators the save uses: `Saml.entity_id_problem` and `Saml.sso_url_problem`, plus `no_sso_url` (section 1) and `no_signing_certificates`. An EntityID with surrounding whitespace, or an SSO URL with a fragment, is reported here rather than discovered at save time.
- One Entra-specific advisory in `problems`: `tenant_level_entra_metadata` when the URL host is a Microsoft login host, the path is `/federationmetadata/2007-06/federationmetadata.xml`, and the query has no `appid`. The document fetched is real and parses, but its keys are the tenant's, not the application's, and a certificate picked from it will not verify the app's responses. This is the most likely admin mistake and costs one string comparison to catch.
- Failure responses reuse the `discovery_check.rb` error vocabulary (`invalid_issuer` renamed `invalid_metadata_url`, `blocked_target`, `timeout`, `ssl_error`, `connection_failed`, `http_error`, `discovery_too_large` → `metadata_too_large`, plus `invalid_metadata` for a body the parser rejects and `aggregate_metadata` for a multi-IdP document). The `blocked_target` message stays generic: `Guard::Blocked` carries the resolved IP and must not be echoed (discovery_check.rb:140).

The endpoint never writes. The admin reviews the filled fields and saves; `PutSsoConfig` / `PatchSsoConfig` validate the trio exactly as they do for pasted values.

### 4.2 Fetching

Reuse `Onetime::SsoProvider::DiscoveryFetcher` (discovery_fetcher.rb) as is: HTTPS only, host resolved once through `Onetime::Http::Guard` and every dial pinned to a validated IP, explicit nil proxy, `VERIFY_PEER`, no redirects, total deadline, body cap on declared length and on the stream. Two parameters change:

- `max_bytes`: the default is 256 KiB (`DEFAULT_MAX_BYTES`, :60), ten times the observed Entra document. Keep the constructor argument (:80) rather than subclassing.
- `Accept`: the fetcher hard-codes `application/json` (:122). Add an `accept:` constructor option defaulting to the current value, and pass `application/samlmetadata+xml, application/xml, text/xml` here. Do not gate on the response `Content-Type`: Entra answers `text/xml`, other IdPs answer `application/xml` or `application/samlmetadata+xml`, and some answer `application/octet-stream`. The parser is the gate.

Query strings must be accepted (`?appid=`); confirm the fetcher forwards `uri.request_uri` unchanged and does not normalise the path.

### 4.3 Parsing

New module `Onetime::SsoProvider::IdpMetadata` wrapping the parser:

1. `IdpMetadataParser.new.parse_to_array(body, sso_binding: [...])`. `ArgumentError` ("idp_metadata must contain an IDPSSODescriptor element") and `REXML::ParseException` both map to `invalid_metadata`. More than one element maps to `aggregate_metadata`.
2. From the single hash: keep `idp_entity_id`, `idp_sso_service_url`, `idp_cert_multi[:signing]`, `name_identifier_format`, `valid_until`, `cache_duration`. Discard `idp_cert`, `idp_cert_fingerprint`, `idp_cert_fingerprint_algorithm` and the encryption list. The wrapper's return type has no slot for them, so a future caller cannot reach for them by accident.
3. PEM-wrap each signing entry, parse with `OpenSSL::X509::Certificate` for subject, window and SHA-256 fingerprint, and run `Saml.cert_problem`.

The parser builds a `REXML::Document` directly (:178), not through ruby-saml's hardened loader. REXML 3.4.4 (installed) does not fetch external entities and bounds internal expansion (`REXML::Security.entity_expansion_limit` 10000, `entity_expansion_text_limit` 10240). The body cap bounds input size. Add two fixtures to the spec: a `DOCTYPE` with an internal entity bomb (must raise or produce no usable result, never hang) and a document with an external entity reference (must not touch the network: the test asserts no `Net::HTTP` call).

### 4.4 What is deliberately not prefilled

- `name_id_format`. The parser reports what the IdP advertises; the stored policy stays the admin's choice (`PERSISTENT_NAME_ID_FORMAT` default, transient refused at save, `SamlFields#validate_saml_policy!`). The advertised formats are returned for display beside the existing selector, nothing more.
- `callback_origins`, `allowed_domains`, `display_name`: unrelated to IdP metadata.
- Anything from the `encryption` certificate list. We do not request encrypted assertions (`want_assertions_encrypted: false`, saml.rb `SECURITY`), so an encryption key has no use and must not be offered as a signing certificate. Section 1 explains why this needs saying.
- `idp_slo_service_url` and the attribute names: no SLO support exists, and attribute names are not configuration.

### 4.5 Storing the metadata URL

New record field `idp_metadata_url` on `CustomDomain::SsoConfig`, declared as `encrypted_field ... aad_fields: [:domain_id]` beside the trio (sso_config.rb:179). It is not secret; it is declared this way for the same integrity reason the trio is (sso_config.rb:163), because in Phase 2 it becomes the thing the refresh job trusts. Declaring it that way now avoids a field migration later.

- Accepted by PUT and PATCH for `provider_type: saml`, optional, cleared for other provider types (`SamlFields#provider_attributes`).
- Validated with `Saml.sso_url_problem` (https, plain host, no fragment) plus `SsrfProtection#valid_issuer_host?` (ssrf_protection.rb:48). The server does fetch this URL, unlike the SSO URL; see the `NO SSRF host check` note at saml_fields.rb:24 for why the SSO URL is exempt and this one is not.
- Served by `serialize_sso_config` in plaintext like the trio; `unreadable_fields` covers it.
- **Not a login invariant.** `saml_validation_errors` (sso_config.rb:1029 onward) checks it structurally only when present. An unreadable or malformed metadata URL is listed in `unreadable_fields` and surfaced in the form; it never makes `build_saml_options` (sso_config.rb:1004) raise. The login path stays trio-only in Phase 1 and the URL is not consulted by it.
- Logged by `ChangeLogger` as `changed: true` without the value (add to `SENSITIVE_FIELDS`, change_logger.rb:38, for the same reason the trio is there).

### 4.6 Form

`DomainSsoConfigForm.vue`, inside the `v-if="isSaml"` block (line ~1479): a metadata URL input and a "Fetch from metadata" button above the trio. On success the composable (`useSsoConfig.ts`) writes `idp_entity_id` and `idp_sso_service_url` into `formState` through `updateField`, so `hasUnsavedChanges` and the unchecked-credentials warning behave as for typed input. The certificate goes into `idp_cert` directly when the list has one entry, otherwise a picker (radio list with subject, window, fingerprint, "newest" label, and the server's `problem`) sets it on selection. `problems` render as inline notices; `tenant_level_entra_metadata` renders with the one-line fix (use the App Federation Metadata Url from the application's SAML page).

The button is advisory; the primary action stays "Save and check". `TestConnection` for SAML is local (test_connection.rb:236) and remains the way the admin confirms the filled trio before saving.

Service: `SsoService.fetchIdpMetadataForDomain(extid, { metadata_url })` in `sso.service.ts`, with a zod response schema in `src/schemas/api/domains/responses/sso-config.ts` and the request in `requests/sso-config.ts`. `idp_metadata_url` itself follows the trio through the contract → shape → API chain: `src/schemas/contracts/custom-domain/sso-config.ts` (nullable), `src/schemas/shapes/domains/sso-config.ts` (nullish-tolerant, null preserved, same rolling-deploy comment as the SAML trio), and `unreadable_fields` handling. Strings in `locales/content/en/workspace-organizations.json` under `web.organizations.sso.*`.

### 4.7 Rate limit

Per customer, through `Onetime::Security::PerCustomerRateLimit` (per_customer_rate_limit.rb:49) with a new policy module next to `SsoDiagnosticsRateLimiter`. The endpoint makes one outbound request per call to a customer-chosen host, so the reason to bound it is egress volume from a leaked owner session, not oracle behaviour. 30 per hour is enough for an admin iterating on a URL. Charged after the ownership and entitlement guards, like diagnostics (run_diagnostics.rb:183).

### 4.8 Tests

- `spec/unit/onetime/sso_provider/idp_metadata_spec.rb`: one-cert, four-cert (the Entra common document, recorded as a fixture), one signing plus one distinct encryption cert (asserts the encryption cert is absent from the result), encryption-only (asserts `no_signing_certificates`, and that the parser's `idp_cert` was not used), no `IDPSSODescriptor`, aggregate, no supported binding, entity bomb, external entity, bare base64 to PEM round-trip through `Saml.cert_problem`, and an assertion that the result object has no fingerprint attribute.
- `apps/api/domains/spec/logic/sso_config/fetch_idp_metadata_spec.rb`: guard order, rate limit, each fetcher status mapping, `tenant_level_entra_metadata` advisory, no write to the record.
- `DomainSsoConfigForm.spec.ts`: picker shown for two certificates with none preselected, textarea filled for one, `problem` disables selection, advisory rendered.

Run through `tests/lanes/run --only <path>` while iterating, then the lane before pushing.

### 4.9 Out of Phase 1

No storage of more than one certificate, no scheduled fetch, no metadata signature verification, no change to the verifier or to any invariant comment in `saml.rb` or `request_bound_saml.rb`. The customer's cert rotation still requires an admin to press "Fetch" and save; the difference is that pressing it is the whole job.

## 5. Phase 2: multi-certificate trust anchor and scheduled refresh

### 5.1 Trust anchor becomes a set

Today the anchor is one PEM block: `cert_problem` refuses anything else (saml.rb:396), `SamlFields::FORBIDDEN_PARAMS` refuses `idp_cert_multi` at the API (saml_fields.rb:79), `strategy_options_for` sets only `idp_cert` (saml.rb:306). Rotation needs two certificates trusted at once: the current one and its successor, during the window between Entra publishing the new certificate and activating it.

ruby-saml supports this, and its multi-certificate path is stricter than the single path, which matters for the invariant comments (verified in response.rb and xml_security.rb of 1.18.1):

- Single path (`Response#validate_signature`, response.rb:873 onward, first branch): matches a response-embedded certificate to the pinned one by fingerprint (`idp_cert_fingerprint_algorithm`, pinned to SHA-256 in `Saml.hardened_options`), then verifies with the **embedded** certificate.
- Multi path (same method, `else` branch; `XMLSecurity#validate_document_with_cert`, xml_security.rb): taken whenever `settings.get_idp_cert_multi[:signing]` is non-empty, at which point `idp_cert` and the fingerprint algorithm are not consulted. For each pinned certificate in order: the **first** `//ds:X509Certificate` in the response, if any, is parsed and must equal the pinned certificate by `OpenSSL::X509::Certificate#to_pem` (both re-encoded from DER, so stored line-wrapping and whitespace are irrelevant); the signature is then verified with the **pinned** certificate's bytes. A response with no embedded certificate is tried against each pinned certificate in turn. On the first match the accumulated per-attempt errors are discarded and the loop stops; `check_idp_cert_expiration` then refuses if that matched certificate is expired, even when another pinned certificate is still valid. A response that matches none is refused.

Two consequences: an expired certificate left in the set is never a trust risk (the verifier refuses it), and the set is unordered for verification; "primary" below is a storage and display slot, not a verifier preference.

The move: `strategy_options_for` always emits `idp_cert_multi: { signing: [pem, ...] }` and never `idp_cert`, so there is one verifier path to reason about (recommended over emitting the single form for one-certificate records). `Settings#get_idp_cert_multi` (settings.rb:190) accepts PEM strings and builds the certificate objects. Every comment that describes the fingerprint match-then-embedded verification becomes historical: saml.rb:41-46 and :221-230, request_bound_saml.rb:163-167. Rewrite them to describe the multi path, and re-run `registry_spec` and `request_bound_saml_spec`. `idp_cert_fingerprint_algorithm` can stay in `hardened_options` as belt-and-braces; note in the comment that the multi path does not read it.

Storage: keep `idp_cert` as the **primary** certificate (unchanged semantics for every existing reader: `SsoConfig#idp_cert_not_after` at sso_config.rb:600, serializer `cert_expires_at` at serializers.rb:49-70, diagnostics `certificate_check` at run_diagnostics.rb:482) and add `idp_cert_successors_json`, an encrypted, domain-bound JSON array of additional PEM blocks (each individually passing `cert_problem` with `allow_expired: true` on the model and `false` on the API). Bounded to four entries (Entra's tenant document has four keys; a per-app document has at most two). `#saml_trio` (sso_config.rb:587) grows a fourth key; `build_saml_options` passes the full list.

Display semantics once the set exists: `cert_expires_at` becomes the latest `not_after` across the set and `cert_expired` means every certificate has expired. The serializer also returns the successors with their windows and fingerprints. The form's 30-day notice (section 5.5) keys off the set-wide values.

API: `idp_cert_multi` stays forbidden as a request parameter (it is ruby-saml's spelling, and accepting it would re-open the fingerprint-only shapes); the API field is `idp_cert_successors` (array of PEM). The form shows the primary textarea plus a list of successors with their windows and a remove action.

Model invariant: `saml_validation_errors` validates each successor structurally, same `allow_expired: true` rule as the primary (an expired successor must not make the record uneditable).

### 5.2 What the refresh may change

The refresh job reads the stored `idp_metadata_url`, fetches and parses as in Phase 1, then:

1. **Refuses** to apply anything when the metadata `entityID` differs from the stored `idp_entity_id`. A different EntityID is a different IdP; that is an admin decision, surfaced as a failed refresh outcome, never applied.
2. **Never changes** `idp_sso_service_url`. A changed URL is reported in the outcome, not applied. The URL is where the browser is sent to enter credentials; a metadata-driven change of it is the exact move a compromised metadata host would make.
3. **Adds** signing certificates from the metadata that are not yet stored, each passing `cert_problem` (window and key type), as successors, up to the bound. A metadata document with more new certificates than free slots applies none and reports `successor_limit`.
4. **Promotes** the successor with the latest `not_after` to primary when the primary has expired. Promotion happens on the job, not at login: the login path has no writer. Because verification is unordered (5.1), promotion is housekeeping for the display slot, not a trust change.
5. **Removes** stored certificates that the metadata no longer lists. Entra removes a retired certificate from metadata when it is deleted from the app, which can happen before it expires; keeping it until expiry means a response signed with the old certificate during the switch-over minute still verifies, at the cost of trusting a deactivated key for its remaining lifetime. With Entra's three-year certificates and the customer rolling early, that remaining lifetime can be long. Decision needed: remove on absence (tighter) or on expiry (safer against a race). Recommended: remove on absence, after the metadata has been read successfully twice without it, so a transient bad read cannot shrink the trust set. Expired certificates are removed on sight; the verifier would refuse them anyway.

Every applied change goes through the model's guarded write (`Onetime::Models::Features::GuardedConfigWrites`, the WATCH-and-retry path PUT/PATCH use via `guarded_config_write`, apps/api/domains/logic/base.rb:56), so a concurrent admin edit wins and the job retries on its next run.

### 5.3 Trust on refresh

With Phase 2, whoever controls the metadata URL controls which signatures the tenant accepts. Two tiers:

- **Auto-apply allowlist**: hosts whose metadata is served by the IdP vendor over TLS and where the trust is already placed in the vendor. A new explicit constant in `Onetime::SsoProvider::IdpMetadata`: `login.microsoftonline.com`, `login.microsoftonline.us`, `login.partner.microsoftonline.cn`. This is not derived from the Entra provider: `entra.rb` hard-pins the commercial cloud and `registry.rb:86-91` directs sovereign Entra to the OIDC provider, so there is no existing host list to reuse. The fetch is TLS-verified and IP-pinned, so this is the same trust the OIDC/Entra path places in the discovery document.
- **Everything else**: fetch, diff, and report. The diff (new certificate fingerprints, missing fingerprints, changed URL, changed EntityID) is shown in the settings page with an "Apply" action that goes through the normal PATCH, logged by `ChangeLogger` with the admin as actor. No automatic write.

Metadata signature verification (Entra signs the document; `metadata_signed` is an SP-side setting, and ruby-saml has no IdP-metadata signature verifier) is not part of Phase 2. The TLS pin to a vendor host is the trust basis; the allowlist is what keeps that argument honest.

### 5.4 Scheduling

`Onetime::Jobs::Scheduled::SsoMetadataRefreshJob < ScheduledJob` in `lib/onetime/jobs/scheduled/`, registered like `DomainRefreshJob` (domain_refresh_job.rb:60; `every(scheduler, interval, first_in: '5m', overlap: false)`), config under `jobs.sso_metadata_refresh` (`enabled`, `check_interval`, `refresh_interval`, `batch_size`). Single-instance assumption as documented in domain_refresh_job.rb:40-60 (one `bin/ots scheduler` per datastore); two schedulers would double the fetches but, with WATCH writes, not corrupt the record.

Two intervals, not one. The job ticks every `check_interval` (default `1h`) but fetches a record only when its last successful refresh is older than `refresh_interval` (default `24h`) **or** the record is flagged for refresh. The flag is set by the login path when a SAML sign-in on a record with a metadata URL fails at signature verification (the `:saml_signature_invalid` class of refusal in `RequestBoundSAML`), written best-effort into the refresh outcome record (5.5) the same way `SsoSigninOutcome` is written today, at most once per hour per record. The flag never triggers a fetch inline, never changes the login result, and does not bypass the trust tiers in 5.3: for a non-allowlisted host the flag only makes the diff appear sooner.

Why: Microsoft's 24-hour guidance assumes the admin leaves a gap between adding and activating. An admin who adds and activates in one sitting, which an early roller doing routine maintenance will do, breaks sign-in until the next poll. The flag turns a day of outage into an hour, at the cost of one guarded field write on a failure path. Daily alone is the fallback when the flag is never set.

Scope per run: every enabled `saml` record with a non-blank `idp_metadata_url`. `SsoConfig.all` exists (sso_config.rb:898); add an index or a scan filter if the count makes a full walk expensive (today it does not).

### 5.5 Failure mode

- **Last-known-good**: a failed fetch or parse never alters the stored set. Sign-in continues on what is stored.
- **Outcome record**: a runtime sibling of `CustomDomain::SsoSigninOutcome` (sso_signin_outcome.rb), `SsoMetadataRefreshOutcome`: `last_at`, `last_result`, `last_code` (the fetcher status or `entity_id_mismatch`, `sso_url_changed`, `no_signing_certificates`, `successor_limit`, `aggregate_metadata`), `last_applied_at`, fingerprints added and removed on the last applied run, `refresh_requested_at` (the flag from 5.4), bound to `signin_outcome_generation` (sso_config.rb:214) so a replaced record does not inherit history, 90-day TTL, best-effort writes. Separate from `SsoConfig` for the reason that file states: the owner-written, audited record's `updated` stamp must not move on a job tick that changed nothing.
- **Diagnostics**: a new `metadata` check in `RunDiagnostics` for saml records (run_diagnostics.rb:305 lists `%w[certificate]` today): `passed` when the last refresh succeeded within two refresh intervals, `failed` with the last code otherwise, `skipped` when no metadata URL is stored. The `certificate` check reports the whole set, so "primary expires in 12 days, successor valid from today" reads as healthy.
- **Warning**: the form's 30-day notice (`CERT_EXPIRY_NOTICE_DAYS`, DomainSsoConfigForm.vue:373) fires on the set-wide `cert_expires_at` (5.1), so a trusted successor silences it. With a stored metadata URL and no successor it says the metadata has not published one yet; with a failing refresh it points at the `metadata` check. The runbook (`docs/runbooks/sso-credential-health.md`, "SAML certificate expiry") gains the job, the flag and the outcome record.
- **Audit**: `log_config_change_event` (apps/api/domains/logic/config_change_logger.rb:40) reads `actor.custid`, `actor.email` and `extract_ip_address` from the request. A job has neither an actor nor a request. Add a system-actor variant that logs `actor_id: 'system:sso_metadata_refresh'`, no email, no IP, same event shape, so an applied rotation appears in the organization's trail. Decision needed on whether the operator trail should see it too.

## 6. Decisions needed

1. **Phase 1 scope**: ship the picker (section 3) rather than "prefill the first certificate". Recommended: picker. Prefilling an inactive certificate is a silent sign-in break, the thing the customer asked us to remove.
2. **Successor removal rule** (5.2 item 5): on absence after two consecutive reads, or on expiry. Recommended: absence after two reads.
3. **Auto-apply allowlist** (5.3): the three Microsoft hosts only at launch, or Microsoft plus Google (`accounts.google.com`) and Okta tenant hosts (`*.okta.com`), which also serve metadata over vendor TLS. Recommended: Microsoft only; add vendors as customers ask, each with the same TLS-pin argument written down.
4. **Failure-triggered refresh** (5.4): include the flag in Phase 2, or ship daily-only and add the flag if a customer hits the same-day activation case. Recommended: include it; the write path already exists for `SsoSigninOutcome` and the alternative is a day of outage that the customer will attribute to us.
5. **Audit actor for job-applied changes** (5.5): organization trail only, or both trails.
6. **Ticketing**: Phase 1 as one PR against the customer request; Phase 2 as its own issue (model change, verifier change, job, flag, diagnostics, runbook), with the `saml.rb` / `request_bound_saml.rb` invariant rewrite called out as a review item.

## 7. Files touched

Phase 1:

- `lib/onetime/sso_provider/discovery_fetcher.rb` (accept header option)
- `lib/onetime/sso_provider/idp_metadata.rb` (new: parse via `parse_to_array`, aggregate refusal, signing-only extraction, PEM-wrap, per-certificate report, Entra tenant-level advisory)
- `apps/api/domains/logic/sso_config/fetch_idp_metadata.rb` (new), `routes.txt`, `logic.rb`
- `lib/onetime/security/sso_metadata_fetch_rate_limiter.rb` (new policy on `PerCustomerRateLimit`)
- `lib/onetime/models/custom_domain/sso_config.rb` (`idp_metadata_url`, structural-only validation), `saml_fields.rb`, `serializers.rb`, `change_logger.rb`, `put_sso_config.rb`, `patch_sso_config.rb`
- `src/services/sso.service.ts`, `src/schemas/api/domains/{requests,responses}/sso-config.ts`, `src/schemas/contracts/custom-domain/sso-config.ts`, `src/schemas/shapes/domains/sso-config.ts`, `src/shared/composables/useSsoConfig.ts`, `DomainSsoConfigForm.vue`, `locales/content/en/workspace-organizations.json`
- specs listed in 4.8

Phase 2 adds:

- `lib/onetime/sso_provider/saml.rb` (`strategy_options_for` multi form, comment rewrite), `request_bound_saml.rb` (comment rewrite, refresh-flag write on signature refusal), `sso_config.rb` (successors field, `saml_trio`, `build_saml_options`, `saml_validation_errors`, set-wide `idp_cert_not_after`)
- `lib/onetime/sso_provider/idp_metadata.rb` (auto-apply host allowlist)
- `lib/onetime/jobs/scheduled/sso_metadata_refresh_job.rb`, `etc/defaults/config.defaults.yaml` (`jobs.sso_metadata_refresh`)
- `lib/onetime/models/custom_domain/sso_metadata_refresh_outcome.rb`, `run_diagnostics.rb` (`metadata` check, set-aware `certificate` check), `serializers.rb` (successors, set-wide expiry), `config_change_logger.rb` (system actor)
- `docs/runbooks/sso-credential-health.md`, and this document moved out of Draft once the behaviour ships

## 8. Sources

- Microsoft Learn, "Tutorial: Manage certificates for federated single sign-on" (Entra ID): ISV guidance on metadata polling cadence and secondary certificates; behaviour when the active certificate has expired; "Make certificate active" semantics; default and maximum certificate lifetime. https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/tutorial-manage-certificates-for-federated-single-sign-on
- ruby-saml 1.18.1 source: `lib/onelogin/ruby-saml/idp_metadata_parser.rb` (parse_to_hash :158, parse_to_array :173, parse_to_idp_metadata_array :177, get_idp_metadata :194, certificates :350, merge_certificates_into :406), `lib/onelogin/ruby-saml/response.rb` (validate_signature :873), `lib/xml_security.rb` (validate_document_with_cert), `lib/onelogin/ruby-saml/settings.rb` (get_idp_cert_multi :190).
