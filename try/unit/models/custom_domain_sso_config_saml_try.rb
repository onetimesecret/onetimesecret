# try/unit/models/custom_domain_sso_config_saml_try.rb
#
# frozen_string_literal: true

# CustomDomain::SsoConfig — provider_type 'saml' against the REAL datastore
# (#4450).
#
# The SAML trio (idp_sso_service_url, idp_entity_id, idp_cert) is stored in
# encrypted_fields bound to domain_id through AAD. None of the three is a
# secret; the binding is there for INTEGRITY — a value copied in from another
# domain's record must fail to decrypt rather than silently re-point this
# domain's logins at a different IdP. That property, and the create! ordering
# question below, can only be pinned with real encryption and a real
# save/load, so this is a tryout rather than a stubbed spec.
#
# CREATE! ORDERING. SsoConfig.create! assigns its encrypted fields BEFORE
# save; MailerConfig.create! assigns its AAD-bound api_key AFTER save, with a
# comment that Familia's build_aad consults record.exists?. On Familia 2.12
# build_aad reads the class name, field name, identifier and the aad_fields
# VALUES only — nothing about existence — so both orderings round-trip. The
# cases below pin that for the pre-existing client_id path AND the new trio:
# reveal on the instance create! returned, and again after a fresh load.
# RE-VERIFY on a Familia bump.
#
# Run:
#   tests/lanes/run unit --only try/unit/models/custom_domain_sso_config_saml_try.rb

require 'openssl'

require_relative '../../support/test_models'

OT.boot! :test

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)

# One self-signed certificate per run; no key material is checked in.
def build_cert_pem(not_after: Time.now + 86_400)
  key             = OpenSSL::PKey::RSA.new(2048)
  cert            = OpenSSL::X509::Certificate.new
  cert.version    = 2
  cert.serial     = SecureRandom.random_number(2**32)
  cert.subject    = OpenSSL::X509::Name.parse('/CN=tryout-idp.example.com')
  cert.issuer     = cert.subject
  cert.public_key = key.public_key
  cert.not_before = [Time.now, not_after].min - 3600
  cert.not_after  = not_after
  cert.sign(key, OpenSSL::Digest.new('SHA256'))
  cert.to_pem
end

@cert_pem    = build_cert_pem
@expired_pem = build_cert_pem(not_after: Time.now - 60)
@sso_url     = 'https://idp.example.com/saml/sso'
@entity_id   = 'https://idp.example.com/saml/metadata'

@owner    = Onetime::Customer.create!(email: "saml_owner_#{@ts}_#{@entropy}@test.com")
@org      = Onetime::Organization.create!("SAML Test Org #{@ts}", @owner, "saml_#{@ts}_#{@entropy}@test.com")
@domain   = Onetime::CustomDomain.create!("saml-a-#{@ts}-#{@entropy}.example.com", @org.objid)
@domain_b = Onetime::CustomDomain.create!("saml-b-#{@ts}-#{@entropy}.example.com", @org.objid)
@oidc_dom = Onetime::CustomDomain.create!("saml-c-#{@ts}-#{@entropy}.example.com", @org.objid)

@klass = Onetime::CustomDomain::SsoConfig

# --- Constants ---

## 'saml' is a configurable tenant provider type
@klass::PROVIDER_TYPES.include?('saml')
#=> true

## SAML has no client credential
[@klass.client_credentials?('saml'), @klass.client_credentials?('oidc'), @klass.client_credentials?('entra_id')]
#=> [false, true, true]

# --- create! : the pre-existing client_id path (ordering question) ---

## client_id set BEFORE save reveals on the instance create! returned
@oidc = @klass.create!(
  domain_id: @oidc_dom.identifier,
  provider_type: 'oidc',
  issuer: 'https://auth.example.com',
  client_id: "client-#{@entropy}",
  client_secret: "secret-#{@entropy}",
  enabled: true,
)
@oidc.client_id.reveal { it }
#=> "client-#{@entropy}"

## ... and again after a fresh load (post-save AAD == pre-save AAD)
@klass.find_by_domain_id(@oidc_dom.identifier).client_id.reveal { it }
#=> "client-#{@entropy}"

# --- create! : the SAML trio ---

## create! accepts a saml config with no client_id / client_secret
@saml = @klass.create!(
  domain_id: @domain.identifier,
  provider_type: 'saml',
  display_name: 'Corp SAML',
  idp_sso_service_url: @sso_url,
  idp_entity_id: @entity_id,
  idp_cert: @cert_pem,
  enabled: true,
)
[@saml.provider_type, @saml.client_id, @saml.valid?]
#=> ['saml', nil, true]

## The trio reveals on the instance create! returned
@saml.saml_trio
#=> { idp_sso_service_url: @sso_url, idp_entity_id: @entity_id, idp_cert: @cert_pem }

## The trio reveals after a fresh load
@loaded = @klass.find_by_domain_id(@domain.identifier)
@loaded.saml_trio
#=> { idp_sso_service_url: @sso_url, idp_entity_id: @entity_id, idp_cert: @cert_pem }

## The values are ciphertext at rest, not plaintext
@raw = Familia.dbclient.hget(@loaded.dbkey, 'idp_entity_id').to_s
[@raw.include?(@entity_id), @raw.include?('ciphertext')]
#=> [false, true]

## The trio survives a commit_fields update of an unrelated field
@loaded.display_name = 'Renamed'
@loaded.commit_fields
@klass.find_by_domain_id(@domain.identifier).reveal_saml_field(:idp_entity_id)
#=> @entity_id

## The platform route name follows SAML_ROUTE_NAME's default
@loaded.platform_route_name
#=> 'saml'

# --- to_omniauth_options ---

## The saml arm names the subclass strategy and carries the trio verbatim
@options = @loaded.to_omniauth_options
[@options[:strategy], @options[:idp_sso_service_url], @options[:idp_entity_id], @options[:idp_cert]]
#=> [:request_bound_saml, @sso_url, @entity_id, @cert_pem]

## It carries the FULL shared security hash (single builder, not a copy)
@options[:security] == Onetime::SsoProvider::Saml::SECURITY
#=> true

## It resets uid_attribute explicitly so a platform value cannot leak in
[@options.key?(:uid_attribute), @options[:uid_attribute]]
#=> [true, nil]

## It never carries an :issuer, SP identifiers or a fingerprint
[:issuer, :sp_entity_id, :assertion_consumer_service_url, :idp_cert_fingerprint].select { |k| @options.key?(k) }
#=> []

# --- AAD binding: a trust anchor swapped in from another domain ---

## A second domain gets its own, different IdP
@other = @klass.create!(
  domain_id: @domain_b.identifier,
  provider_type: 'saml',
  idp_sso_service_url: 'https://evil-idp.example.net/sso',
  idp_entity_id: 'https://evil-idp.example.net/metadata',
  idp_cert: @cert_pem,
  enabled: true,
)
@other.reveal_saml_field(:idp_entity_id)
#=> 'https://evil-idp.example.net/metadata'

## Copying domain B's ciphertext into domain A's hash makes the field unreadable
@stolen = Familia.dbclient.hget(@other.dbkey, 'idp_entity_id')
Familia.dbclient.hset(@loaded.dbkey, 'idp_entity_id', @stolen)
@swapped = @klass.find_by_domain_id(@domain.identifier)
begin
  @swapped.reveal_saml_field(:idp_entity_id)
  :revealed
rescue StandardError
  :refused
end
#=> :refused

## ... the record reports the field as unreadable, not as unset
@swapped.validation_errors
#=> ['idp_entity_id cannot be read (re-enter the value)']

## ... and to_omniauth_options refuses rather than injecting a partial trio
begin
  @swapped.to_omniauth_options
  :built
rescue Onetime::Problem => ex
  ex.message.include?('unreadable')
end
#=> true

# --- Validation ---

## All three fields are required for saml
@blank = @klass.new(domain_id: "blank_#{@entropy}", provider_type: 'saml')
@blank.validation_errors
#=> ['idp_sso_service_url is required for SAML provider', 'idp_entity_id is required for SAML provider', 'idp_cert is required for SAML provider']

## An http SSO URL is refused
@bad = @klass.new(domain_id: "bad_#{@entropy}", provider_type: 'saml')
@bad.idp_sso_service_url = 'http://idp.example.com/sso'
@bad.idp_entity_id = @entity_id
@bad.idp_cert = @cert_pem
@bad.validation_errors
#=> ['IdP SSO service URL must be an https:// URL']

## An SSO URL with a fragment is refused (ruby-saml appends ?SAMLRequest= by concatenation)
@bad.idp_sso_service_url = 'https://idp.example.com/sso#login'
@bad.validation_errors
#=> ['IdP SSO service URL must not contain a fragment']

## An SSO URL whose host yields no CSP-safe origin is refused at the model too (one rule)
@bad.idp_sso_service_url = 'https://idp.example.com;/sso'
@bad.validation_errors
#=> ['IdP SSO service URL must have a plain hostname (no spaces, quotes or punctuation in the host)']

## Something that is not a PEM certificate is refused
@bad.idp_sso_service_url = @sso_url
@bad.idp_cert = 'AA:BB:CC:DD'
@bad.validation_errors
#=> ['IdP certificate must be a PEM X.509 certificate (-----BEGIN CERTIFICATE-----)']

## An EXPIRED certificate does not invalidate the record (it must stay editable) ...
@bad.idp_cert = @expired_pem
@bad.validation_errors
#=> []

## ... but it is refused where the certificate is USED
begin
  @bad.to_omniauth_options
  :built
rescue Onetime::Problem => ex
  ex.message.include?('expired')
end
#=> true

## oidc still requires client_id
@klass.new(domain_id: "oidc_#{@entropy}", provider_type: 'oidc', issuer: 'https://a.example.com').validation_errors
#=> ['client_id is required']

# Teardown — scoped to what this file created (no FLUSHDB: the datastore is
# shared with every other file in the run).
[@domain, @domain_b, @oidc_dom].each do |dom|
  @klass.delete_for_domain!(dom.identifier)
  dom.destroy!
end
@org.destroy!
@owner.destroy!
