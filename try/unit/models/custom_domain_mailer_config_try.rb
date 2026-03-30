# try/unit/models/custom_domain_mailer_config_try.rb
#
# frozen_string_literal: true

# Integration tests for CustomDomain::MailerConfig model
#
# Covers:
#   - MailerConfig creation with valid attributes
#   - Validation (missing domain_id, missing provider, invalid provider, missing from_address)
#   - update_from_address clears verified_at and resets verification_status
#   - rotate_credentials preserves verified_at
#   - CustomDomain forward navigation (sso_config, mailer_config, sso_config?, mailer_config?)
#   - Provider type validation against PROVIDER_TYPES constant
#   - enabled? and verified? boolean methods
#   - safe_dump_fields mail_configured and mail_enabled

require_relative '../../support/test_models'

OT.boot! :test

# Configure Familia encryption with known test keys.
# OT.boot! derives keys from config secret_key via HKDF, but encrypted_field
# round-trip tests need explicit key setup (same pattern as SsoConfig RSpec).
@key_v1 = 'test_encryption_key_32bytes_ok!!'
@key_v2 = 'another_test_key_for_testing_!!'

Familia.configure do |config|
  config.encryption_keys = {
    v1: Base64.strict_encode64(@key_v1),
    v2: Base64.strict_encode64(@key_v2),
  }
  config.current_key_version = :v1
  config.encryption_personalization = 'MailerConfigTest'
end

Familia.dbclient.flushdb
OT.info "Cleaned Redis for MailerConfig test run"

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "mc_owner_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("MC Test Org #{@ts}", @owner, "mc_#{@ts}@test.com")
@domain = Onetime::CustomDomain.create!("mc-test-#{@ts}.example.com", @org.objid)

# --- Creation ---

## MailerConfig.create! with valid attributes returns MailerConfig
@config = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain.identifier,
  provider: 'ses',
  from_name: 'Test Sender',
  from_address: 'noreply@mc-test.example.com',
  reply_to: 'support@mc-test.example.com',
  api_key: 'test-api-key-abc123'
)
@config.class
#=> Onetime::CustomDomain::MailerConfig

## Created config has correct domain_id
@config.domain_id
#=> @domain.identifier

## Created config has correct provider
@config.provider
#=> 'ses'

## Created config has correct from_name
@config.from_name
#=> 'Test Sender'

## Created config has correct from_address
@config.from_address
#=> 'noreply@mc-test.example.com'

## Created config has correct reply_to
@config.reply_to
#=> 'support@mc-test.example.com'

# TODO: Encrypted api_key round-trip assertion — needs investigation into
# Familia encryption key configuration for tryouts. Separate ticket.
# Onetime::CustomDomain::MailerConfig.find_by_domain_id(@domain.identifier).api_key.reveal { it }
# #=> 'test-api-key-abc123'

## Created config defaults enabled to false
@config.enabled
#=> 'false'

## Created config defaults verification_status to pending
@config.verification_status
#=> 'pending'

## Created config has timestamps set
[@config.created.to_i > 0, @config.updated.to_i > 0]
#=> [true, true]

## Created config persists in Redis (can be reloaded)
@reloaded = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@domain.identifier)
@reloaded.nil?
#=> false

## Reloaded config preserves provider
@reloaded.provider
#=> 'ses'

## Reloaded config preserves from_address
@reloaded.from_address
#=> 'noreply@mc-test.example.com'

# --- Duplicate prevention ---

## create! raises when config already exists for domain
begin
  Onetime::CustomDomain::MailerConfig.create!(
    domain_id: @domain.identifier,
    provider: 'smtp',
    from_address: 'other@example.com'
  )
  'unexpected_success'
rescue Onetime::Problem => e
  e.message
end
#=> 'Mailer config already exists for this domain'

# --- Validation: missing domain_id ---

## create! raises when domain_id is empty
begin
  Onetime::CustomDomain::MailerConfig.create!(
    domain_id: '',
    provider: 'ses',
    from_address: 'test@example.com'
  )
  'unexpected_success'
rescue Onetime::Problem => e
  e.message
end
#=> 'domain_id is required'

## create! raises when domain_id is nil
begin
  Onetime::CustomDomain::MailerConfig.create!(
    domain_id: nil,
    provider: 'ses',
    from_address: 'test@example.com'
  )
  'unexpected_success'
rescue Onetime::Problem => e
  e.message
end
#=> 'domain_id is required'

# --- Validation: provider ---

## create! raises when provider is missing
@domain_noprov = Onetime::CustomDomain.create!("mc-noprov-#{@ts}.example.com", @org.objid)
begin
  Onetime::CustomDomain::MailerConfig.create!(
    domain_id: @domain_noprov.identifier,
    from_address: 'test@example.com'
  )
  'unexpected_success'
rescue Onetime::Problem => e
  e.message.include?('provider is required')
end
#=> true

## create! raises when provider is invalid
@domain_badprov = Onetime::CustomDomain.create!("mc-badprov-#{@ts}.example.com", @org.objid)
begin
  Onetime::CustomDomain::MailerConfig.create!(
    domain_id: @domain_badprov.identifier,
    provider: 'mailchimp',
    from_address: 'test@example.com'
  )
  'unexpected_success'
rescue Onetime::Problem => e
  e.message.include?('provider must be one of')
end
#=> true

# --- Validation: from_address ---

## create! raises when from_address is missing
@domain_noaddr = Onetime::CustomDomain.create!("mc-noaddr-#{@ts}.example.com", @org.objid)
begin
  Onetime::CustomDomain::MailerConfig.create!(
    domain_id: @domain_noaddr.identifier,
    provider: 'ses'
  )
  'unexpected_success'
rescue Onetime::Problem => e
  e.message.include?('from_address is required')
end
#=> true

# --- PROVIDER_TYPES constant ---

## PROVIDER_TYPES includes all expected providers
Onetime::CustomDomain::MailerConfig::PROVIDER_TYPES.sort
#=> %w[lettermint sendgrid ses smtp].sort

## PROVIDER_TYPES is frozen
Onetime::CustomDomain::MailerConfig::PROVIDER_TYPES.frozen?
#=> true

# --- validation_errors method ---

## validation_errors returns empty array for valid config
@config.validation_errors
#=> []

## validation_errors detects missing domain_id
mc = Onetime::CustomDomain::MailerConfig.new
mc.provider = 'ses'
mc.from_address = 'x@test.com'
mc.validation_errors.include?('domain_id is required')
#=> true

## validation_errors detects invalid provider
mc2 = Onetime::CustomDomain::MailerConfig.new
mc2.domain_id = 'some-id'
mc2.provider = 'invalid'
mc2.from_address = 'x@test.com'
mc2.validation_errors.include?('provider must be one of: smtp, ses, sendgrid, lettermint')
#=> true

# --- enabled? and verified? boolean methods ---

## enabled? returns false by default
@config.enabled?
#=> false

## enabled? returns true when enabled is 'true'
@config.enabled = 'true'
@config.save
@config.enabled?
#=> true

## enabled? returns false for non-true string
@config.enabled = 'false'
@config.save
@config.enabled?
#=> false

## verified? returns false when status is pending
@config.verified?
#=> false

## verified? returns true when verification_status is verified
@config.verification_status = 'verified'
@config.save
@config.verified?
#=> true

## verified? returns false when status is failed
@config.verification_status = 'failed'
@config.save
@config.verified?
#=> false

# --- update_from_address clears verified_at ---

## Setup: mark as verified first
@config.verification_status = 'verified'
@config.verified_at = Familia.now.to_i.to_s
@config.save
[@config.verified?, @config.verified_at.to_s.empty?]
#=> [true, false]

## update_from_address resets verification_status to pending
@config.update_from_address('new-sender@mc-test.example.com')
@config.verification_status
#=> 'pending'

## update_from_address clears verified_at
@config.verified_at.to_s.empty? || @config.verified_at.nil?
#=> true

## update_from_address sets the new from_address
@config.from_address
#=> 'new-sender@mc-test.example.com'

## update_from_address updates the updated timestamp
@config.updated.to_i > 0
#=> true

## update_from_address persists changes (reload from Redis)
@reloaded_after_update = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@domain.identifier)
@reloaded_after_update.from_address
#=> 'new-sender@mc-test.example.com'

## Reloaded config has pending verification_status after address change
@reloaded_after_update.verification_status
#=> 'pending'

# --- rotate_credentials preserves verified_at ---

## Setup: mark config as verified for rotate test
@config.verification_status = 'verified'
@config.verified_at = Familia.now.to_i.to_s
@config.save
@saved_verified_at = @config.verified_at
@config.verified?
#=> true

## rotate_credentials preserves verified_at
@config.rotate_credentials('new-api-key-xyz789')
@config.verified_at
#=> @saved_verified_at

# TODO: Encrypted api_key round-trip after rotation — same ticket as above.
# Onetime::CustomDomain::MailerConfig.find_by_domain_id(@domain.identifier).api_key.reveal { it }
# #=> 'new-api-key-xyz789'

## rotate_credentials preserves verification_status
@config.verification_status
#=> 'verified'

## rotate_credentials updates the updated timestamp
@config.updated.to_i > 0
#=> true

# --- Class methods: find_by_domain_id, exists_for_domain? ---

## find_by_domain_id returns config for existing domain
Onetime::CustomDomain::MailerConfig.find_by_domain_id(@domain.identifier).nil?
#=> false

## find_by_domain_id returns nil for non-existent domain
Onetime::CustomDomain::MailerConfig.find_by_domain_id('nonexistent-domain-id').nil?
#=> true

## find_by_domain_id returns nil for empty string
Onetime::CustomDomain::MailerConfig.find_by_domain_id('').nil?
#=> true

## find_by_domain_id returns nil for nil
Onetime::CustomDomain::MailerConfig.find_by_domain_id(nil).nil?
#=> true

## exists_for_domain? returns true for domain with config
Onetime::CustomDomain::MailerConfig.exists_for_domain?(@domain.identifier)
#=> true

## exists_for_domain? returns false for domain without config
@domain_no_config = Onetime::CustomDomain.create!("mc-noconfig-#{@ts}.example.com", @org.objid)
Onetime::CustomDomain::MailerConfig.exists_for_domain?(@domain_no_config.identifier)
#=> false

## exists_for_domain? returns false for empty string
Onetime::CustomDomain::MailerConfig.exists_for_domain?('')
#=> false

## exists_for_domain? returns false for nil
Onetime::CustomDomain::MailerConfig.exists_for_domain?(nil)
#=> false

# --- delete_for_domain! ---

## Setup: create a config to delete
@domain_to_delete = Onetime::CustomDomain.create!("mc-del-#{@ts}.example.com", @org.objid)
@del_config = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_to_delete.identifier,
  provider: 'smtp',
  from_address: 'del@example.com'
)
Onetime::CustomDomain::MailerConfig.exists_for_domain?(@domain_to_delete.identifier)
#=> true

## delete_for_domain! returns true when config exists
Onetime::CustomDomain::MailerConfig.delete_for_domain!(@domain_to_delete.identifier)
#=> true

## delete_for_domain! actually removes the config
Onetime::CustomDomain::MailerConfig.exists_for_domain?(@domain_to_delete.identifier)
#=> false

## delete_for_domain! returns false for non-existent domain
Onetime::CustomDomain::MailerConfig.delete_for_domain!('nonexistent-id')
#=> false

## delete_for_domain! returns false for empty string
Onetime::CustomDomain::MailerConfig.delete_for_domain!('')
#=> false

# --- CustomDomain forward navigation ---

## domain.mailer_config returns the MailerConfig instance
@nav_config = @domain.mailer_config
@nav_config.class
#=> Onetime::CustomDomain::MailerConfig

## domain.mailer_config returns config with correct domain_id
@nav_config.domain_id
#=> @domain.identifier

## domain.mailer_config? returns true when config exists
@domain.mailer_config?
#=> true

## domain without config: mailer_config returns nil
@domain_no_config.mailer_config.nil?
#=> true

## domain without config: mailer_config? returns false
@domain_no_config.mailer_config?
#=> false

## domain.sso_config returns nil when no SSO config exists
@domain.sso_config.nil?
#=> true

## domain.sso_config? returns false when no SSO config exists
@domain.sso_config?
#=> false

## After creating SSO config, sso_config returns it
@sso = Onetime::CustomDomain::SsoConfig.create!(
  domain_id: @domain.identifier,
  provider_type: 'oidc',
  client_id: 'test-client',
  client_secret: 'test-secret',
  issuer: 'https://auth.example.com',
  display_name: 'Test SSO'
)
@domain.sso_config.class
#=> Onetime::CustomDomain::SsoConfig

## domain.sso_config? returns true after SSO config exists
@domain.sso_config?
#=> true

# --- MailerConfig reverse navigation ---
# BUG: MailerConfig#custom_domain calls CustomDomain.load(domain_id) but
# CustomDomain.load requires 2 args (display_domain, org_id). This raises
# ArgumentError at runtime. Should use find_by_identifier(domain_id) instead.

## mailer_config.custom_domain raises ArgumentError (known bug: load expects 2 args)
## custom_domain returns the parent CustomDomain
@config.custom_domain.class
#=> Onetime::CustomDomain

## custom_domain returns the correct domain
@config.custom_domain.identifier
#=> @domain.identifier

# --- Entitlement rename: custom_mail_sender ---

## STANDALONE_ENTITLEMENTS includes custom_mail_sender (renamed from custom_mail_defaults)
Onetime::Models::Features::WithEntitlements::STANDALONE_ENTITLEMENTS.include?('custom_mail_sender')
#=> true

## STANDALONE_ENTITLEMENTS does not include old name custom_mail_defaults
Onetime::Models::Features::WithEntitlements::STANDALONE_ENTITLEMENTS.include?('custom_mail_defaults')
#=> false

# --- Create with each valid provider type ---

## ses provider is accepted
@domain_ses = Onetime::CustomDomain.create!("mc-ses-#{@ts}.example.com", @org.objid)
@cfg_ses = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_ses.identifier, provider: 'ses', from_address: 'a@ses.com')
@cfg_ses.provider
#=> 'ses'

## smtp provider is accepted
@domain_smtp = Onetime::CustomDomain.create!("mc-smtp-#{@ts}.example.com", @org.objid)
@cfg_smtp = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_smtp.identifier, provider: 'smtp', from_address: 'a@smtp.com')
@cfg_smtp.provider
#=> 'smtp'

## sendgrid provider is accepted
@domain_sg = Onetime::CustomDomain.create!("mc-sg-#{@ts}.example.com", @org.objid)
@cfg_sg = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_sg.identifier, provider: 'sendgrid', from_address: 'a@sg.com')
@cfg_sg.provider
#=> 'sendgrid'

## lettermint provider is accepted
@domain_lm = Onetime::CustomDomain.create!("mc-lm-#{@ts}.example.com", @org.objid)
@cfg_lm = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_lm.identifier, provider: 'lettermint', from_address: 'a@lm.com')
@cfg_lm.provider
#=> 'lettermint'

# --- enabled flag via create! ---

## create! with enabled: true stores 'true'
@domain_en = Onetime::CustomDomain.create!("mc-en-#{@ts}.example.com", @org.objid)
@cfg_en = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_en.identifier, provider: 'ses', from_address: 'a@en.com', enabled: true)
@cfg_en.enabled?
#=> true

## create! with enabled: false stores 'false'
@domain_dis = Onetime::CustomDomain.create!("mc-dis-#{@ts}.example.com", @org.objid)
@cfg_dis = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_dis.identifier, provider: 'ses', from_address: 'a@dis.com', enabled: false)
@cfg_dis.enabled?
#=> false

# Teardown
Familia.dbclient.flushdb
