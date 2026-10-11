# apps/api/domains/spec/logic/sso_config/serializers_spec.rb
#
# frozen_string_literal: true

# Unit tests for SsoConfig::Serializers — the certificate-expiry fields
# (#4450). An expired IdP certificate stays advertised on the sign-in page
# (availability never checks expiry, by design) while every login through it
# is refused as sso_config_unusable; cert_expired / cert_expires_at are how
# the admin learns why.
#
# Certificates are minted here with OpenSSL; no key material is checked in.
#
# RUN (always via the lane runner — see AGENTS.md):
#   tests/lanes/run unit --only apps/api/domains/spec/logic/sso_config/serializers_spec.rb

require 'base64'
require 'openssl'
require 'time'

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'
require_relative File.join(Onetime::HOME, 'apps', 'web', 'auth', 'spec', 'support', 'domain_sso_test_fixtures')

RSpec.describe DomainsAPI::Logic::SsoConfig::Serializers do
  include DomainSsoTestFixtures

  # encrypted_field needs key configuration; same setup as the model spec.
  before(:all) do
    @original_encryption_keys = Familia.config.encryption_keys&.dup
    @original_key_version     = Familia.config.current_key_version
    @original_personalization = Familia.config.encryption_personalization

    Familia.configure do |config|
      config.encryption_keys            = { v1: Base64.strict_encode64('test_encryption_key_32bytes_ok!!') }
      config.current_key_version        = :v1
      config.encryption_personalization = 'SsoSerializers'
    end
  end

  after(:all) do
    Familia.configure do |config|
      config.encryption_keys            = @original_encryption_keys if @original_encryption_keys
      config.current_key_version        = @original_key_version if @original_key_version
      config.encryption_personalization = @original_personalization if @original_personalization
    end
  end

  let(:serializer) { Class.new { include DomainsAPI::Logic::SsoConfig::Serializers }.new }

  def mint_cert_pem(not_after:)
    key             = OpenSSL::PKey::RSA.new(2048)
    cert            = OpenSSL::X509::Certificate.new
    cert.version    = 2
    cert.serial     = 1
    cert.subject    = OpenSSL::X509::Name.parse('/CN=serializer-spec-idp.example.com')
    cert.issuer     = cert.subject
    cert.public_key = key.public_key
    cert.not_before = not_after - 86_400
    cert.not_after  = not_after
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
    cert.to_pem
  end

  def saml_config_with_cert(pem)
    build_domain_sso_config(:saml).tap { |config| config.idp_cert = pem }
  end

  describe '#saml_sp_identifiers' do
    let(:config) { build_domain_sso_config(:saml) }
    let(:custom_domain) do
      instance_double(
        Onetime::CustomDomain,
        display_domain: 'secrets.example.com',
        verified: verified,
      )
    end
    let(:verified) { true }

    before do
      allow(config).to receive(:custom_domain).and_return(custom_domain)
      allow(OT).to receive(:conf).and_return('site' => { 'ssl' => true })
    end

    let(:tenant_identifiers) do
      {
        sp_entity_id: 'https://secrets.example.com/auth/sso/saml/metadata',
        acs_url: 'https://secrets.example.com/auth/sso/saml/callback',
      }
    end

    it 'returns tenant-host identifiers for a verified domain' do
      expect(serializer.saml_sp_identifiers(config)).to eq(tenant_identifiers)
    end

    # #4579: the values to register at the IdP, live once verification
    # completes. The tenant hook refuses SSO on the domain until then
    # (sso_domain_unverified), so the IdP never receives anything else.
    context 'when domain ownership is unverified' do
      let(:verified) { false }

      it 'still returns the tenant-host identifiers, never the canonical host' do
        expect(serializer.saml_sp_identifiers(config)).to eq(tenant_identifiers)
      end
    end

    context 'when the domain has no display_domain' do
      let(:custom_domain) do
        instance_double(Onetime::CustomDomain, display_domain: '  ', verified: true)
      end

      it 'returns both identifiers as nil' do
        expect(serializer.saml_sp_identifiers(config)).to eq(sp_entity_id: nil, acs_url: nil)
      end
    end

    context 'when the domain cannot be loaded' do
      let(:custom_domain) { nil }

      it 'returns both identifiers as nil' do
        expect(serializer.saml_sp_identifiers(config)).to eq(sp_entity_id: nil, acs_url: nil)
      end
    end

    it 'returns both identifiers as nil for a non-saml record' do
      oidc = build_domain_sso_config(:oidc)
      allow(oidc).to receive(:custom_domain).and_return(custom_domain)

      expect(serializer.saml_sp_identifiers(oidc)).to eq(sp_entity_id: nil, acs_url: nil)
    end
  end

  # #4734 (RISK-2026-10-10-01): tenant SSO creates an account only for an
  # address inside a domain the organization has proven, so the record names
  # the proven set and the allowlist entries that admit no one. Judged by
  # Organization#owns_email_domain? (real), over doubled domains.
  describe '#serialize_sso_config email domain proof' do
    let(:organization) { Onetime::Organization.allocate }

    def domain_double(id, name, verified:)
      instance_double(
        Onetime::CustomDomain,
        identifier: id, display_domain: name, ownership_verified: verified,
        primary_organization: organization,
      )
    end

    let(:own_domain)   { domain_double('dom-own', 'secrets.acme.com', verified: true) }
    let(:apex_domain)  { domain_double('dom-apex', 'beispiel.org', verified: true) }
    let(:idn_domain)   { domain_double('dom-idn', 'xn--bcher-kva.org', verified: true) }
    let(:unproven)     { domain_double('dom-unproven', 'pending.org', verified: false) }
    let(:org_domains)  { [own_domain, apex_domain, idn_domain, unproven] }
    let(:allowed)      { [] }
    let(:config)       { build_domain_sso_config(:oidc, allowed_domains: allowed) }
    let(:payload)      { serializer.serialize_sso_config(config) }

    before do
      allow(config).to receive(:custom_domain).and_return(own_domain)
      allow(organization).to receive(:verified_domains).and_return(org_domains.select(&:ownership_verified))
    end

    it 'lists the proven domains sorted, the config domain included once' do
      expect(payload[:verified_email_domains]).to eq(
        %w[beispiel.org secrets.acme.com xn--bcher-kva.org],
      )
    end

    context 'with allowlist entries of every kind' do
      let(:allowed) do
        [
          'secrets.acme.com',       # equals a verified domain
          'team.secrets.acme.com',  # below a verified domain
          'acme.com',                   # above: only the subdomain is proven
          'pending.org',            # equals a custom domain whose ownership is not proven
          'bücher.org',             # Unicode spelling of a verified A-label domain
          'notacme.com',            # shares a suffix, not a label boundary
        ]
      end

      it 'names only the entries outside every proven domain, as stored' do
        expect(payload[:unverified_allowed_domains]).to eq(
          %w[acme.com pending.org notacme.com],
        )
      end
    end

    context 'when the config domain itself is not proven and the index is empty' do
      let(:own_domain)  { domain_double('dom-own', 'secrets.acme.com', verified: false) }
      let(:org_domains) { [own_domain] }
      let(:allowed)     { ['secrets.acme.com'] }

      it 'reports no proven domain and the entry as unverified' do
        expect(payload).to include(verified_email_domains: [], unverified_allowed_domains: ['secrets.acme.com'])
      end
    end

    context 'when the domain has no organization' do
      let(:allowed) { ['secrets.acme.com'] }

      before do
        allow(config).to receive(:custom_domain).and_return(
          instance_double(Onetime::CustomDomain, primary_organization: nil),
        )
      end

      it 'treats every entry as unverified' do
        expect(payload).to include(verified_email_domains: [], unverified_allowed_domains: ['secrets.acme.com'])
      end
    end

    context 'when the domain cannot be loaded' do
      before { allow(config).to receive(:custom_domain).and_return(nil) }

      it 'serves empty arrays rather than raising' do
        expect(payload).to include(verified_email_domains: [], unverified_allowed_domains: [])
      end
    end

    context 'when the lookup raises' do
      before { allow(config).to receive(:custom_domain).and_raise(Redis::CannotConnectError, 'down') }

      it 'serves empty arrays and keeps the rest of the record' do
        allow(OT).to receive(:lw)
        expect(payload).to include(verified_email_domains: [], unverified_allowed_domains: [])
        expect(payload[:domain_id]).to eq(config.domain_id)
      end
    end
  end

  describe '#serialize_sso_config certificate expiry' do
    context 'with an expired certificate' do
      let(:not_after) { Time.at(Time.now.to_i - 3600).utc }
      let(:payload)   { serializer.serialize_sso_config(saml_config_with_cert(mint_cert_pem(not_after: not_after))) }

      it 'flags cert_expired' do
        expect(payload[:cert_expired]).to be(true)
      end

      it 'reports cert_expires_at as ISO 8601 UTC' do
        expect(payload[:cert_expires_at]).to eq(not_after.iso8601)
      end

      it 'does not name idp_cert as unreadable (expired is not undecryptable)' do
        expect(payload[:unreadable_fields]).to eq([])
      end
    end

    context 'with a current certificate' do
      let(:not_after) { Time.at(Time.now.to_i + (30 * 86_400)).utc }
      let(:payload)   { serializer.serialize_sso_config(saml_config_with_cert(mint_cert_pem(not_after: not_after))) }

      it 'reports the expiry without flagging it' do
        expect(payload).to include(cert_expired: false, cert_expires_at: not_after.iso8601)
      end
    end

    context 'with a certificate OpenSSL cannot parse' do
      let(:payload) { serializer.serialize_sso_config(saml_config_with_cert("-----BEGIN CERTIFICATE-----\nnope\n-----END CERTIFICATE-----")) }

      it 'serves null / false rather than raising' do
        expect(payload).to include(cert_expires_at: nil, cert_expired: false)
      end
    end

    context 'with a non-saml record' do
      let(:payload) { serializer.serialize_sso_config(build_domain_sso_config(:oidc)) }

      it 'serves null / false' do
        expect(payload).to include(cert_expires_at: nil, cert_expired: false)
      end
    end
  end
end
