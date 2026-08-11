# docs/specs/custom-mail-sender/custom-mail-sender-structural-issues.md

---

Structural gaps (make every new provider expensive/risky):

- No provider descriptor. Adding smtp2go touched ~19 registries/case-arms: PROVIDER_STRATEGIES, PROVISIONING_PROVIDERS, validation PROVIDER_MAP, ProviderConfig::DEFAULTS, PROVIDER_TYPES, 3 case arms in mailer.rb, missing_credential_keys, config_summary, zod enum, Vue map. Each drifts independently — proof: config_summary shipped without lettermint and nobody noticed.
- Credential resolution exists in ~5 places with different semantics: YAML ERB defaults, ProviderConfig merge, build_provider_config arms, config_summary's own raw+ENV helpers, strategy-level fallbacks. Same bounce/track/base-URL defaults live in up to 4 layers.
- Required-credential knowledge lives only in ProvisionSenderDomain.missing_credential_keys. DomainValidationWorker guards on credentials.empty?; smtp2go_provider_config now returns {} when its api_key is absent so the guard works there, but lettermint's YAML api_base_url default still makes its hash non-empty → a rotated lettermint key silently flips verified domains to failed.
- Error classification is split: classify_error on backends (good) vs send_test_email#domain_not_provisioned_error? hardcoding Lettermint error shapes (bad — providers should classify their own errors).
- Provider capability surfaces (provider_status, recent_messages, feedback sync) are per-provider case statements plus Data.define(:ses, :lettermint) members mirrored in the colonel TS schema — adding stats for a provider is a breaking wire-shape change, not a registration.
- Two parallel DNS layers persist (fact-finding vs validation). RecordMatcher unified matching, but required_dns_records/classify_record_purpose are still near-identical boilerplate ×4 validation classes.

Aberrations (inconsistencies, mostly historical):

- Auto-detect chain in determine_provider sniffs emailer keys (lettermint_api_token, now smtp2go_api_key) that no YAML ever defines — dead path; .env.reference documents a nonexistent emailer.sendgrid_api_key.
- Three HTTP stacks: sendgrid-ruby gem (eagerly required in lib/onetime.rb, against the lazy-require pattern), inline Net::HTTP in SendGrid strategy, Smtp2goClient. Lettermint gem is the only lazy one.
- send_test_email builds BYOK backends inline instead of via the factory — where the symbol-key bug lived (Base now stringifies, but the bypass remains).
- 'optional' => true is the only record-semantics hint; the apex plan's match: flag (needed for MailChannels apex SPF) is still unimplemented.
- log_error Sentry blocks are cloned per backend and send from/subject unscrubbed.
- 30 locales carry unused provider\_\* keys while display names are hardcoded in DomainEmailConfigForm.vue.
- No test covers any create_delivery_backend arm; provider_credentials_contract_try monkeypatches Mailer.emailer_config without restore, forcing one-file-per-process runs.

Worth fixing first: provider descriptor object (collapses the registries and the credential/default duplication), worker required-key guard, backend-owned error classification. The rest is tolerable drift.
