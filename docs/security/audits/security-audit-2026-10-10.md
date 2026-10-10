# Security Audit — 2026-10-10: Tenant SSO email claims (G3 review)

- **Report:** G3 (gate G3 of the [SSO email-less accounts proposal](../../planning/2026-1009-sso-email-less-accounts.md))
- **Register:** `RISK-2026-10-10-01` … `RISK-2026-10-10-03`, added to the [active register](../active-risk-register.md) on 2026-10-10. **Status pointer:** the operator rated all three Medium on 2026-10-10; the ratings in this report are the audit's own assessment and are retained as written.
- **Scope:** The custom-domain (tenant) SSO surface: automatic account verification (including an absent `email_verified`), trusted-email linking, and email-domain authorization, each measured against what the identity provider actually guarantees about the `email` claim. Platform and self-hosted operators configure their own identity providers and own that trust; their surfaces are noted only where the same code path is shared. `ENTRA_TENANT_ID` is a directory UUID in every supported configuration; `common` and `organizations` are out of scope.
- **Source-review baseline:** `3a30ad2eeb91b0927658d534c4a8dd6aceb9451d` (branch `fix/4726-legacy-email-repair`, merge-base with `main` `af99322661559ed611cca5324f659b7b1e2a880e`). The working tree carried uncommitted changes to the #4726 CLI and doctor files only; every file this audit relies on was unmodified at the baseline.
- **Probe baseline:** same revision. Probes ran through the lane runner against the dockerized test services (`full-sqlite` and `full-mfa` lanes), using the OmniAuth mock strategy on the `oidc` route with Entra-shaped claim sets. The real Entra route was not exercised.
- **Gem versions:** omniauth-entra-id 3.1.1, omniauth_openid_connect 0.8.0, omniauth-google-oauth2 1.2.3, omniauth-github 2.0.1, omniauth-saml 2.2.5, rodauth-omniauth 0.6.2.
- **Method:** Targeted source inspection, provider documentation quoted verbatim, and five executable probes (appendix) whose results are recorded below. The probe file was not committed.

> **Historical record.** This report captures the available evidence, not a security guarantee or acceptance decision. It proposes remediations; it approves none. The [active security risk register](../active-risk-register.md) tracks current disposition.

## Conclusion and severity

One confirmed High finding, one Medium, one Low. Two of the three review items hold on the tenant surface: trusted-email linking is excluded by construction, and an asserted address that already belongs to a platform account is refused. The third item does not hold: the tenant allowlist judges an `email` claim that no supported tenant provider vouches for, the allowlist is the tenant's own choice (empty means allow-all), and a passing claim mints a canonical-pool account that is stamped verified without mailbox proof. The address owner's later password reset or magic link then signs into that account while the tenant identity stays linked (probes P1–P3). This is account squatting with persistent shared control, reachable by anyone who administers a verified custom domain's identity provider.

Rating basis: exploitability Moderate (requires a tenant with a verified custom domain and SSO configured, and control of its identity provider or of a user's `mail` attribute); impact High (any unregistered address, persistent access to the victim's later account, denial of normal sign-up, unsolicited credential email to the victim). Existing platform accounts are not exposed: H-3 refuses them.

## Provider guarantees (primary wording)

| Source | Exact wording | Bearing on this review |
|---|---|---|
| [Microsoft ID token claims reference, `email`](https://learn.microsoft.com/en-us/entra/identity-platform/id-token-claims-reference#payload-claims) | "Present by default for guest accounts that have an email address. Your app can request the email claim for managed users (from the same tenant as the resource) using the `email` optional claim. This value isn't guaranteed to be correct and is mutable over time. Never use it for authorization or to save data for a user." | The tenant allowlist and the JIT account's login column are both authorization and saved data derived from this claim. |
| [Microsoft, Secure applications and APIs by validating claims](https://learn.microsoft.com/en-us/entra/identity-platform/claims-validation#validate-the-subject) | "Never use claims like `email`, `preferred_username` or `unique_name` to store or determine whether the user in an access token should have access to data. These claims aren't unique and can be controllable by tenant administrators or sometimes users, which make them unsuitable for authorization decisions." | Names the threat actor for S1: the tenant administrator (and, in some tenants, the user). |
| [Microsoft optional claims reference, `xms_edov`](https://learn.microsoft.com/en-us/entra/identity-platform/optional-claims-reference#v10-and-v20-optional-claims-set) | "Boolean value indicating whether the user's email domain owner has been verified." Notes: "An email is considered to be domain verified if it belongs to the tenant where the user account resides and the tenant admin has done verification of the domain. […] For this claim to be returned in the token, the presence of the `email` claim is required." | The one provider signal at the domain level. It is domain-owner verification, not mailbox control. OTS never reads it (no occurrence of `xms_edov` in `apps/`, `lib/`, or `src/`). |
| [Microsoft Graph, Manage application authenticationBehaviors](https://learn.microsoft.com/en-us/graph/applications-authenticationbehaviors#prevent-the-issuance-of-email-claims-with-unverified-domain-owners) | "apps should never use the email claim for authorization purposes". Risk scenario: "When the **mail** attribute of the user object contains an email address with an unverified domain owner". Default: "Today, the default behavior is to remove email addresses with unverified domain owners in claims, except for single-tenant apps and for multitenant apps with previous sign-in activity with unverified emails." | A tenant's Entra app registration for OTS is single-tenant (UUID `tenant_id`), so Microsoft's default removal does not apply: unverified-domain `email` claims are issued unless the tenant sets `removeUnverifiedEmailClaim: true`. |
| [OpenID Connect Core 1.0 §5.1, `email_verified`](https://openid.net/specs/openid-connect-core-1_0.html#StandardClaims) | "True if the End-User's e-mail address has been verified; otherwise false. When this Claim Value is true, this means that the OP took affirmative steps to ensure that this e-mail address was controlled by the End-User at the time the verification was performed. The means by which an e-mail address is verified is context specific, and dependent upon the trust framework or contractual agreements within which the parties are operating." | A `true` is a provider assertion inside its own trust framework. Absence asserts nothing. |

Strategy behaviour at the pinned versions (source inspection of the installed gems):

| Provider (tenant-capable) | Where `info.email` comes from | `email_verified` | Issuer check |
|---|---|---|---|
| Entra ID (omniauth-entra-id 3.1.1) | `raw_info['email']`, the decoded id_token payload; the decoded access-token payload is merged over it (`id_token_data.merge!(auth_token_data)`), and that second decode skips signature verification. | Never emitted by Microsoft; never set by the strategy. | `iss` verified against `https://login.microsoftonline.com/<tenant_id>/v2.0` for a UUID tenant; skipped only for `common`/nil. |
| Generic OIDC (omniauth_openid_connect 0.8.0) | `user_info.email`; UserInfo attributes with the decoded id_token merged over them. | Passed through as `info.email_verified` when the IdP sends it. | Per discovery and token verification (and OTS's #4513 install-issuer check on the platform path). |
| SAML (omniauth-saml 2.2.5) | Mapped attribute. | No such claim; an attribute literally named `email_verified` holding `false` is honoured as a hold. | Response Issuer bound to the tenant record (#4450). |

Google and GitHub are issuerless and are refused on tenant surfaces, so their stronger behaviour (Google nils `info.email` unless `email_verified` is true; GitHub returns only the primary verified address under `user:email`) does not reach this review's scope.

## Source evidence

| Component | Observed behaviour | Limitation |
|---|---|---|
| [features/omniauth.rb](../../../apps/web/auth/config/features/omniauth.rb) lines 65–67 | `omniauth_verify_account? true` with the comment "SSO providers handle email verification, so we trust them". Every JIT account opens at `Verified`. | The comment states a design intent, not a provider guarantee; for Entra and SAML no verification claim exists. |
| [hooks/omniauth.rb](../../../apps/web/auth/config/hooks/omniauth.rb) `email_verification_hold` (around line 1059) | Holds only on an explicit `false` or an unreadable claim. Absence is not a hold, by design (Entra, OAuth2 strategies, GitHub never emit it). | Narrows the stamp; cannot widen it. Correct as far as it goes, but it means an Entra JIT account is always stamped verified. |
| [hooks/omniauth.rb](../../../apps/web/auth/config/hooks/omniauth.rb) `after_omniauth_create_account` (around lines 870–895) | Customer stamped `verified: true, verified_by: 'sso'` when the accounts row is `Verified` and no hold exists. | `verified_by: 'sso'` is later consumed as if it were mailbox verification (see S3). |
| [hooks/omniauth_tenant.rb](../../../apps/web/auth/config/hooks/omniauth_tenant.rb) `enforce_tenant_email_domain!` (line 669) | Fail-closed ladder on every tenant callback: no config, corrupt list, missing email, malformed email, domain not listed. An empty list is allow-all. | The list is set by the tenant; the asserted address is set by the tenant's IdP. Both sides of the comparison are under one party's control. |
| [sso_config.rb](../../../lib/onetime/models/custom_domain/sso_config.rb) `valid_email_domain?` (line 348) and `PROVIDER_METADATA` (lines 74–92) | Exact string match after `downcase`; subdomains do not match. Entra metadata: `requires_domain_filter: false`, `idp_controls_access: true`, "access controlled via Azure app assignment". | App assignment controls who may authenticate at the IdP, not which address namespace the token asserts. |
| [hooks/omniauth.rb](../../../apps/web/auth/config/hooks/omniauth.rb) trust branch (around lines 207–231) | Trusted-email auto-link requires `session[:validated_omniauth_domain_id].nil?`, i.e. the platform surface. | Verified by the existing spec `omniauth_trusted_link_spec.rb` ("tenant path, trust flag ON (must still refuse)"). No tenant finding. |
| [hooks/omniauth.rb](../../../apps/web/auth/config/hooks/omniauth.rb) H-3 branch and `before_omniauth_create_account` (lines 722–790) | An asserted address matching an existing account is refused on the tenant surface (`tenant_sso_link_unavailable`). A new address passes the signup-domain gate (per-domain `SignupConfig` or global `allowed_signup_domains`) and is created. | On the platform deployment the global signup allowlist is normally empty, so the create gate adds nothing on the tenant surface. |
| [hooks/reset_password_request.rb](../../../apps/web/auth/config/hooks/reset_password_request.rb), [features/email_auth.rb](../../../apps/web/auth/config/features/email_auth.rb) | Canonical-host password reset and magic-link requests check rate limits and the public host. Neither checks whether the account has a password, how it was provisioned, or whether its address was ever mailbox-verified. | Rodauth's defaults insert a password hash on reset for an account that has none. |
| [operations/join_domain_organization.rb](../../../apps/web/auth/operations/join_domain_organization.rb) lines 83–95 | A tenant JIT account becomes a member of the tenant organization (domain-scoped unless `grant_org_scope`). The account itself lives in the shared `accounts` table under the asserted email. | [ADR-035](../../adr/adr-035-tenant-identity-auth-policy-scope.md) records the shared-pool behaviour as "a known, long-standing gap". |
| Consumers of `Customer#verified?` | [authorization_policies.rb:56](../../../lib/onetime/application/authorization_policies.rb) (`has_system_role?`), [show_secret.rb](../../../apps/api/v2/logic/secrets/show_secret.rb) and [reveal_secret.rb](../../../apps/api/v2/logic/secrets/reveal_secret.rb) owner checks, [ensure_default_workspace.rb](../../../apps/web/auth/operations/ensure_default_workspace.rb) `claim_pending_federation`, [create_account.rb:102](../../../apps/api/account/logic/account/create_account.rb). | None distinguishes `verified_by: 'sso'` from `'email'`. |

## Scenarios and results

Probe outcomes are from the appendix file. `full-sqlite`: 6 examples, 0 failures, 1 pending (P3 needs magic links). `full-mfa`: P1, P2, P3 and P4 passed; the P5 variant in that run used a `.example` TLD that the PublicSuffix validator rejects and was corrected for the `full-sqlite` run.

| ID | Scenario | Preconditions | Observed on baseline | Evidence |
|---|---|---|---|---|
| S1 | A tenant's IdP asserts `email` for an address outside any namespace the tenant owns and that has no OTS account. | Verified custom domain with SSO; attacker controls the IdP or the user's `mail` attribute (Entra: tenant admin; Microsoft notes "sometimes users"). Allowlist empty, or listing the chosen domain. | Account created at `Verified`, Customer `verified_by: 'sso'`, no hold, tenant membership added, session authenticated. `xms_edov: false` in the claims changes nothing. | P1 (both allowlist cases), P4 pass |
| S2 | The address owner later requests a password reset or magic link on the canonical host. | S1 account exists; owner receives mail at the address. | Reset succeeds and inserts a password hash; magic link signs in. The `(provider, issuer, uid)` row minted by the tenant IdP is untouched, so the tenant identity and the owner's new credential both sign into the same account. | P2, P3 pass |
| S3 | `verified_by: 'sso'` is consumed as mailbox verification. | Any S1 account. | `has_system_role?`, owner-gated secret display, and `claim_pending_federation` accept the account as verified. No provider domain-verification signal (`xms_edov`) is requested or read. | Source table; P4 |
| S4 | Trusted-email linking on the tenant surface. | Any `*_TRUST_EMAIL_FOR_LINKING=true`. | Refused by construction; the tenant callback falls through to H-3. | `omniauth_trusted_link_spec.rb` (existing) |
| S5 | A tenant IdP asserts an address that already belongs to a platform account. | Existing account, not linked to this identity. | Refused with `tenant_sso_link_unavailable`; no identity row. | `omniauth_trusted_link_spec.rb`, `omniauth_signin_interstitial_spec.rb` (existing) |
| S6 | A returning tenant identity's IdP stops sending `email` (for example after `removeUnverifiedEmailClaim: true`) while the allowlist is nonempty. | Linked identity. | Denied with `missing_email` on every sign-in; identity row retained. Fail-closed by design; availability impact for the tenant. | `omniauth_missing_email_spec.rb` "returning identity" (existing) |
| S7 | Allowlist stored in one IDN form, address asserted in the other. | IDN domain. | Unicode and A-label forms do not match each other; exact byte comparison. Fail-closed. | P5 pass |
| S8 | Entra single-tenant registration receives unverified-domain `email` claims by default. | Tenant has not set `removeUnverifiedEmailClaim: true`. | Not executable here; from Microsoft's wording above. Feeds S1 for Entra tenants. | Provider table |

## Risk disposition

| Proposed ID | Scenario | Rating | Proposed status | Notes |
|---|---|---|---|---|
| RISK-2026-10-10-01 | S1 + S2 + S8 | **High** (P2) | Open | Tenant-minted canonical-pool account for an arbitrary unregistered address; persistent shared control after the owner's reset or magic link. Related: [ADR-035](../../adr/adr-035-tenant-identity-auth-policy-scope.md) shared-pool gap. |
| RISK-2026-10-10-02 | S3 | **Medium** (P3) | Open | `verified_by: 'sso'` satisfies mailbox-verification consumers; no domain-level provider signal consulted. Distinct from RISK-2026-08-14-M01, which concerns an explicit `false`. |
| RISK-2026-10-10-03 | S7 | **Low** (P4) | Open | IDN form mismatch denies legitimate sign-ins; reliability, fail-closed. |
| none | S4, S5 | — | — | Mechanisms hold on the tenant surface; existing specs cover them. |
| none | S6 | — | — | By design. Document the operator-facing consequence of `removeUnverifiedEmailClaim` (R2). |
| none | absence of `email_verified` on the platform surface | — | — | Owned by RISK-2026-08-14-M01 (#4688). Out of this review's scope per the operator's decision. |

## Proposed remediations (not approved)

Ordered by impact. Each needs a separate decision; none is implied by this document.

1. **R1 — Bind tenant-minted accounts to proven namespaces (durable fix for 01).** Tenant SSO may create an account only when the asserted address's domain is one the organization has proven: a DNS-verified custom domain name or a new email-domain verification record. The allowlist then selects among proven domains instead of being free text, and the Entra allow-all mode applies to the proven set only. App assignment keeps controlling *who* authenticates; domain proof controls *which addresses* the tenant may mint. This also aligns the tenant path with [ADR-035](../../adr/adr-035-tenant-identity-auth-policy-scope.md) (org-scoped accounts, never canonical-pool accounts).
2. **R1a — Interim gate on canonical-host credential issuance (02 and the S2 half of 01).** Refuse `reset-password-request` and `email-login-request` for an account whose only credential is a tenant SSO identity and whose address has never been mailbox-verified, with a message directing the user to sign in through their organization. Alternatively, when such an account first gains a mailbox-proven credential, require explicit re-linking of SSO identities and notify the address. Either option removes the shared-control outcome without touching the allowlist semantics.
3. **R2 — Entra-specific hardening (01, S8).** (a) Operator guidance and the Test Connection check: recommend `removeUnverifiedEmailClaim: true` on the tenant's app registration, since single-tenant registrations are excluded from Microsoft's default; OTS then fails closed through the existing `missing_email` rung. (b) Request the `xms_edov` optional claim and honour an explicit `false` as a new verification hold (`domain_unverified`) and as an allowlist refusal. Absence stays a non-hold (M01 scope). (c) Amend the `PROVIDER_METADATA` description and `per-domain-sso.md`: app assignment is access control at the IdP, not evidence about the `email` claim's domain.
4. **R3 — Split verification semantics (02).** Introduce a mailbox-verified predicate for consumers that mean mailbox control (`has_system_role?`, owner-gated secret display, `claim_pending_federation`, account creation checks), and keep `verified_by: 'sso'` as "IdP-asserted". Extend the customers doctor to report accounts whose only verification is `'sso'` and that hold a platform credential.
5. **R4 — IDN normalization (03).** Normalize allowlist entries and asserted domains to A-label form before comparison and log a distinct reason when the forms differed.

## Validation

- `tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/g3_review_probe_spec.rb` → 6 examples, 0 failures, 1 pending (P3 skipped: magic links off in this lane).
- `tests/lanes/run full-mfa --only apps/web/auth/spec/integration/full/g3_review_probe_spec.rb` → P1 (×2), P2, P3, P4 passed; P5 failed only in its earlier `.example`-TLD form, later corrected and passed in `full-sqlite`.
- The probe file was removed from the tree after the runs. It is reproduced in the appendix so the scenarios can be re-run at a later baseline.
- Not validated: the real `/auth/sso/entra` route with a Microsoft-issued token, and whether a given tenant's Entra registration emits unverified-domain `email` claims. The planning document's acceptance evidence requires that live round before any related release.

## Appendix: probe specification (not committed)

```ruby
# frozen_string_literal: true

# G3 REVIEW PROBE — TEMPORARY. Not for commit. Reproduction evidence for
# docs/security/audits/security-audit-2026-10-10.md (tenant SSO email claims).
# Run:
#   tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/g3_review_probe_spec.rb
#   tests/lanes/run full-mfa    --only apps/web/auth/spec/integration/full/g3_review_probe_spec.rb  (P3)
require_relative '../../spec_helper'
require_relative '../../support/oauth_flow_helper'
require 'cgi'

RSpec.describe 'G3 probe: tenant SSO email claims', type: :integration do
  include Rack::Test::Methods
  include_context 'domains enabled'

  before(:all) { boot_onetime_app }

  let(:run_id) { SecureRandom.hex(6) }
  let(:host) { "g3-#{run_id}.tenant.example.com" }
  let(:uid) { "oid-#{SecureRandom.uuid}" }
  let!(:tenant) { setup_oauth_test_domain(host) }
  # An address in a namespace the tenant does not own and that has no account.
  let(:squatted_email) { "victim-#{run_id}@unrelated.example.org" }

  before do
    configure_allowed_domains(nil)
    @delivered = []
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw) do |email, **_kwargs|
      @delivered << email
      true
    end
  end

  after do
    teardown_mock_auth
    customer = Onetime::Customer.find_by_email(squatted_email)
    if customer
      Onetime::OrganizationMembership.find_by_org_customer(tenant[:org].objid, customer.objid)&.destroy!
      customer.destroy!
    end
    cleanup_oauth_test_fixtures
    clear_auth_database
  end

  # Entra-shaped claim set via the mock strategy: tid+oid identity, an `email`
  # claim, no email_verified, and whatever extra raw_info the example adds.
  def claim_hash(email, raw_extra = {})
    OmniAuth::AuthHash.new(
      provider: 'oidc',
      uid: uid,
      info: { email: email, name: 'Probe User' },
      credentials: { token: 'mock_access_token', expires: false },
      extra: {
        raw_info: {
          sub: uid, oid: uid, tid: "tenant-#{run_id}",
          preferred_username: "probe@#{run_id}.onmicrosoft.com",
        }.merge(raw_extra),
      },
    )
  end

  def tenant_callback(email, raw_extra = {})
    enable_omniauth_test_mode
    OmniAuth.config.mock_auth[:oidc] = claim_hash(email, raw_extra)
    clear_body_headers
    header 'Host', host
    post '/auth/sso/oidc'
    expect(last_response.status).to eq(302), last_response.body
    expect(last_request.env['rack.session']['omniauth_tenant_domain_id']).to eq(tenant[:domain].identifier)
    clear_body_headers
    post '/auth/sso/oidc/callback'
    expect(last_response.status).not_to eq(404), 'SSO route must be registered'
  end

  def expect_minted_verified_account
    expect(last_response.status).to eq(302), last_response.body
    expect(last_response.location.to_s).not_to include('auth_error='), last_response.location.to_s
    account = auth_db[:accounts].where(email: squatted_email).first
    expect(account).not_to be_nil
    expect(account[:status_id]).to eq(AuthTestConstants::STATUS_VERIFIED)
    customer = Onetime::Customer.find_by_email(squatted_email)
    expect(customer).not_to be_nil
    expect(customer.provisioning_origin.to_s).to eq('sso_jit')
    expect(customer.verified?).to be(true)
    expect(customer.verified_by.to_s).to eq('sso')
    expect(customer.verification_hold.to_s).to eq('')
    expect(Onetime::OrganizationMembership.find_by_org_customer(tenant[:org].objid, customer.objid)).not_to be_nil
    expect(last_request.env['rack.session'].to_h).to include('authenticated' => true, 'account_id' => account[:id])
    account
  end

  def emailed_key(path)
    expect(@delivered.size).to eq(1), "expected one delivered email, got #{@delivered.size}: #{last_response.status} #{last_response.body.to_s[0, 300]}"
    email = @delivered.first
    expect(email[:to]).to eq([squatted_email])
    link = email[:body].to_s[%r{https?://\S+?#{Regexp.escape(path)}\?key=\S+}]
    expect(link).not_to be_nil, "missing #{path} link in delivered email"
    CGI.parse(URI.parse(link).query).fetch('key').first
  end

  [[], ['unrelated.example.org']].each do |allowlist|
    it "P1: tenant IdP mints a verified account for an address outside the tenant (allowlist #{allowlist.inspect})" do
      tenant[:sso_config].allowed_domains = allowlist
      tenant[:sso_config].save
      tenant_callback(squatted_email)
      expect_minted_verified_account
    end
  end

  it 'P2: the address owner can set a password on the squatted account by reset while the tenant identity stays linked' do
    tenant_callback(squatted_email)
    account = expect_minted_verified_account
    expect(auth_db[:account_password_hashes].where(id: account[:id]).count).to eq(0)

    clear_cookies
    header 'Host', canonical_host
    csrf_json_post('/auth/reset-password-request', login: squatted_email)
    expect(last_response.status).to eq(200), last_response.body
    key          = emailed_key('/reset-password')
    new_password = "Pr0be-#{SecureRandom.hex(8)}!"
    csrf_json_post('/auth/reset-password', key: key, password: new_password, 'password-confirm': new_password)
    expect(last_response.status).to eq(200), last_response.body
    expect(auth_db[:account_password_hashes].where(id: account[:id]).count).to eq(1)

    # The identity row minted by the tenant IdP is untouched by the reset.
    expect(auth_db[:account_identities].where(provider: 'oidc', uid: uid).all)
      .to contain_exactly(hash_including(account_id: account[:id]))

    # Both credentials now sign in to the same account: the tenant IdP...
    clear_cookies
    tenant_callback(squatted_email)
    expect(last_response.location.to_s).not_to include('auth_error=')
    expect(last_request.env['rack.session'].to_h).to include('authenticated' => true, 'account_id' => account[:id])

    # ...and the new password on the canonical host.
    clear_cookies
    header 'Host', canonical_host
    csrf_login(squatted_email, password: new_password)
    expect(last_request.env['rack.session'].to_h).to include('authenticated' => true, 'account_id' => account[:id])
  end

  it 'P3: the address owner can sign in to the squatted account by magic link while the tenant identity stays linked' do
    skip 'email_auth disabled in this lane (run under full-mfa)' unless Onetime.auth_config.email_auth_enabled?
    tenant_callback(squatted_email)
    account = expect_minted_verified_account

    clear_cookies
    header 'Host', canonical_host
    csrf_json_post('/auth/email-login-request', login: squatted_email)
    expect(last_response.status).to eq(200), last_response.body
    key = emailed_key('/email-login')
    csrf_json_post('/auth/email-login', key: key)
    expect(last_response.status).to eq(200), last_response.body
    expect(last_request.env['rack.session'].to_h).to include('authenticated' => true, 'account_id' => account[:id])
    expect(auth_db[:account_identities].where(provider: 'oidc', uid: uid).all)
      .to contain_exactly(hash_including(account_id: account[:id]))
  end

  it 'P4: an explicit xms_edov: false (domain owner NOT verified) changes nothing — the claim is never read' do
    tenant[:sso_config].allowed_domains = ['unrelated.example.org']
    tenant[:sso_config].save
    tenant_callback(squatted_email, { xms_edov: false, email_verified: nil })
    expect_minted_verified_account
  end

  it 'P5: IDN allowlist forms — the stored form must equal the asserted form byte-for-byte' do
    cfg = tenant[:sso_config]
    cfg.allowed_domains = ['bücher.de']
    expect(cfg.allowed_domains).to eq(['bücher.de'])
    expect(cfg.valid_email_domain?('a@bücher.de')).to be(true)
    expect(cfg.valid_email_domain?('a@xn--bcher-kva.de')).to be(false)
    cfg.allowed_domains = ['xn--bcher-kva.de']
    expect(cfg.valid_email_domain?('a@xn--bcher-kva.de')).to be(true)
    expect(cfg.valid_email_domain?('a@bücher.de')).to be(false)
    expect(Onetime::SignupValidation.structurally_valid_email?('a@bücher.de')).to be(true)
  end
end
```
