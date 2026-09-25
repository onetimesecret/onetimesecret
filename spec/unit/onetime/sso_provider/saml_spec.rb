# spec/unit/onetime/sso_provider/saml_spec.rb
#
# frozen_string_literal: true

# Onetime::SsoProvider::Saml — the per-value rules the platform env, the
# tenant model and the tenant API all share (#4450).
#
#   .sso_url_problem         one rule for the IdP SSO service URL, including
#                            the CSP-origin funnel (AuthConfig.origin_from_url)
#   .session_cookie_problem  the SameSite=None/Lax + Secure prerequisite as code,
#                            shared by .platform_options (provider skipped),
#                            the placeholder boot warning and the API refusal
#   .platform_host?          the host the platform ACS is pinned to at boot
#                            (site.host); descriptive only, since platform
#                            fallback on a verified custom domain rebinds the
#                            ACS per request (OmniAuthTenant.bind_platform_
#                            fallback_acs)
#   .cert_problem            the STRUCTURAL half of the IdP certificate rule:
#                            exactly one PEM CERTIFICATE block and nothing
#                            else (the validity-window half, allow_expired
#                            and the builder are covered in registry_spec)
#
# RUN (always via the lane runner — see AGENTS.md):
#   tests/lanes/run unit --only spec/unit/onetime/sso_provider/saml_spec.rb

require 'spec_helper'
require_relative '../../../../lib/onetime/sso_provider/saml'
require_relative '../../../support/saml/test_idp'

RSpec.describe Onetime::SsoProvider::Saml do
  describe '.sso_url_problem' do
    it 'accepts a plain https URL' do
      expect(described_class.sso_url_problem('https://idp.example.com/saml/sso')).to be_nil
    end

    it 'accepts a non-default port and a query string' do
      expect(described_class.sso_url_problem('https://idp.example.com:8443/sso?tenant=acme')).to be_nil
    end

    it 'strips surrounding whitespace before judging' do
      expect(described_class.sso_url_problem("  https://idp.example.com/sso\n")).to be_nil
    end

    {
      'a blank value' => ['', 'is blank'],
      'an http URL' => ['http://idp.example.com/sso', 'must be an https:// URL'],
      'a schemeless URL' => ['idp.example.com/sso', 'must be an https:// URL'],
      'a hostless URL' => ['https:///sso', 'has no host'],
      'userinfo' => ['https://u:p@idp.example.com/sso', 'must not carry credentials'],
      'a trailing dot on the host' => ['https://idp.example.com./sso', 'must not end with a dot'],
      'an unparseable URL' => ['https://idp example.com/sso', 'is not a valid URL'],
    }.each do |label, (url, message)|
      it "refuses #{label}" do
        expect(described_class.sso_url_problem(url)).to include(message)
      end
    end

    # ruby-saml's Authrequest#create string-concatenates "SAMLRequest=..."
    # onto the URL ("&" after an existing query, "?" otherwise), so a
    # fragment swallows the query and the IdP gets no request at all.
    it 'refuses a fragment' do
      expect(described_class.sso_url_problem('https://idp.example.com/sso#login'))
        .to eq('IdP SSO service URL must not contain a fragment')
    end

    it 'refuses an empty fragment too (URI keeps "" for a bare "#")' do
      expect(described_class.sso_url_problem('https://idp.example.com/sso#'))
        .to eq('IdP SSO service URL must not contain a fragment')
    end

    # URI.parse keeps the ';' on the host, so every structural check above
    # passes — but AuthConfig.origin_from_url derives no origin from it and
    # the CSP form-action / HttpOrigin allowances would silently omit the
    # IdP. One rule, checked through the same funnel those consumers use.
    {
      'a trailing semicolon on the host' => 'https://idp.example.com;/saml/sso',
      'a quote in the host' => %(https://idp.example.com'/saml/sso),
      'a comma in the host' => 'https://idp,example.com/saml/sso',
    }.each do |label, url|
      it "refuses #{label}, which URI.parse accepts but origin_from_url does not" do
        expect(URI.parse(url).host).not_to be_empty
        expect(Onetime::AuthConfig.origin_from_url(url)).to be_nil

        expect(described_class.sso_url_problem(url)).to eq(described_class::SSO_URL_ORIGIN_PROBLEM)
      end
    end

    it 'derives the same origin the CSP layer will carry for an accepted URL' do
      url = 'https://idp.example.com:8443/saml/sso'

      expect(described_class.sso_url_problem(url)).to be_nil
      expect(Onetime::AuthConfig.origin_from_url(url)).to eq('https://idp.example.com:8443')
    end

    it 'refuses when origin_from_url raises, rather than admitting the URL' do
      allow(Onetime::AuthConfig).to receive(:origin_from_url).and_raise(RuntimeError, 'boom')

      expect(described_class.sso_url_problem('https://idp.example.com/sso')).to eq(described_class::SSO_URL_ORIGIN_PROBLEM)
    end
  end

  describe '.session_cookie_problem' do
    it 'is nil for SameSite=None with Secure' do
      expect(described_class.session_cookie_problem('same_site' => 'none', 'secure' => true)).to be_nil
    end

    it 'is case- and whitespace-tolerant on same_site' do
      expect(described_class.session_cookie_problem('same_site' => ' None ', 'secure' => true)).to be_nil
    end

    it 'accepts Lax with Secure for the staged callback' do
      expect(described_class.session_cookie_problem('same_site' => 'lax', 'secure' => true)).to be_nil
      expect(described_class.session_cookie_problem('same_site' => 'lax', 'secure' => false)).to include('secure is false')
    end

    it 'refuses SameSite=None without Secure (a browser drops such a cookie)' do
      problem = described_class.session_cookie_problem('same_site' => 'none', 'secure' => false)

      expect(problem).to include("same_site is 'none'", 'secure is false')
    end

    it 'refuses strict' do
      expect(described_class.session_cookie_problem('same_site' => 'strict', 'secure' => true)).to include("'strict'")
    end

    it 'treats a missing same_site as unset, not as none' do
      expect(described_class.session_cookie_problem('secure' => true)).to include('same_site is unset')
    end

    it 'treats a non-boolean secure as not secure' do
      expect(described_class.session_cookie_problem('same_site' => 'none', 'secure' => 'true')).to include('secure is false')
    end

    it 'reads Onetime.session_config by default' do
      allow(Onetime).to receive(:session_config).and_return('same_site' => 'none', 'secure' => true)

      expect(described_class.session_cookie_problem).to be_nil
    end

    it 'is a problem under the shipped session defaults' do
      expect(described_class.session_cookie_problem(Onetime::Initializers::SESSION_DEFAULTS)).to include('secure is false')
    end
  end

  # OpenSSL::X509::Certificate.new picks the FIRST CERTIFICATE block out of
  # whatever surrounds it, so a check that only counts BEGIN markers accepts
  # "cert + private key". The value is stored whole and served back as
  # public data by the SSO config API, so anything besides the one block is
  # refused here. The expiry / not-yet-valid half lives in registry_spec.
  describe '.cert_problem (structure)' do
    let(:cert) { SamlSpec::TestIdp.new.cert_pem }
    let(:private_key) { SamlSpec::TestIdp.shared_key.to_pem }
    let(:exactly_one) { 'IdP certificate must contain exactly one PEM certificate' }

    it 'accepts one certificate with surrounding whitespace and CRLF line endings' do
      expect(described_class.cert_problem("  \r\n#{cert.gsub("\n", "\r\n")}\r\n  ")).to be_nil
    end

    it 'accepts the deployment one-line form (literal \\n)' do
      expect(described_class.cert_problem(cert.gsub("\n", '\n'))).to be_nil
    end

    it 'refuses a certificate followed by a private key' do
      expect(described_class.cert_problem(cert + private_key)).to eq(exactly_one)
    end

    it 'refuses a private key followed by a certificate' do
      expect(described_class.cert_problem(private_key + cert)).to eq(exactly_one)
    end

    it 'refuses text before and after the certificate' do
      ["Bag Attributes\n    friendlyName: idp\n#{cert}trailing note\n", "junk\n#{cert}", "#{cert}junk"].each do |value|
        expect(described_class.cert_problem(value)).to eq(exactly_one)
      end
    end

    it 'refuses two certificates' do
      expect(described_class.cert_problem(cert + SamlSpec::TestIdp.new.cert_pem)).to eq(exactly_one)
    end

    # OpenSSL parses a truncated block that is immediately followed by a
    # complete one, so the marker count is checked, not only the block count.
    it 'refuses a truncated block followed by a complete certificate' do
      truncated = cert.lines[0..-2].join

      expect(described_class.cert_problem(truncated + cert)).to eq(exactly_one)
    end

    it 'refuses a BEGIN with no END as unparseable' do
      truncated = cert.lines[0..-2].join

      expect(described_class.cert_problem(truncated)).to eq('IdP certificate does not parse as X.509')
    end

    it 'keeps the blank message for nil and whitespace' do
      [nil, "  \n"].each do |value|
        expect(described_class.cert_problem(value)).to eq('IdP certificate is blank')
      end
    end

    it 'keeps the non-PEM message for a value with no CERTIFICATE block at all' do
      expect(described_class.cert_problem(private_key))
        .to eq('IdP certificate must be a PEM X.509 certificate (-----BEGIN CERTIFICATE-----)')
    end

    it 'never puts the value in the message' do
      [cert + private_key, private_key + cert, "SENSITIVE #{cert}"].each do |value|
        expect(described_class.cert_problem(value)).not_to include('PRIVATE KEY', 'SENSITIVE')
      end
    end

    it 'parses the one clean block through .parse_cert' do
      expect(described_class.parse_cert(cert)).to be_a(OpenSSL::X509::Certificate)
    end

    it 'is the same rule for .parse_cert' do
      [cert + private_key, private_key + cert, "junk\n#{cert}", cert.lines[0..-2].join].each do |value|
        expect(described_class.parse_cert(value)).to be_nil
      end
    end
  end

  describe 'NameID policy and certificate setup' do
    require_relative '../../../support/saml/test_idp'
    let(:idp) { SamlSpec::TestIdp.new }
    let(:trio) { { idp_sso_service_url: 'https://idp.example/sso', idp_entity_id: 'urn:idp', idp_cert: idp.cert_pem } }

    it 'generates persistent by default, explicit formats, and no policy when omitted' do
      require 'onelogin/ruby-saml'
      [described_class::PERSISTENT_NAME_ID_FORMAT, 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress', 'omit'].each do |format|
        options  = described_class.strategy_options_for(**trio, name_id_format: format)
        settings = OneLogin::RubySaml::Settings.new(options.merge(sp_entity_id: 'urn:sp', assertion_consumer_service_url: 'https://sp.example/callback'))
        request  = OneLogin::RubySaml::Authrequest.new.create(settings)
        encoded  = URI.decode_www_form(URI(request).query).to_h.fetch('SAMLRequest')
        inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
        xml      = inflater.inflate(Base64.decode64(encoded))
        inflater.close
        node     = Nokogiri::XML(xml).at_xpath('//*[local-name()="NameIDPolicy"]')
        if format == 'omit'
          expect(node).to be_nil
        else
          expect(node['Format']).to eq(format)
        end
      end
      expect(described_class.strategy_options_for(**trio)[:name_identifier_format]).to eq(described_class::PERSISTENT_NAME_ID_FORMAT)
      expect { described_class.strategy_options_for(**trio, name_id_format: 'invalid') }.to raise_error(ArgumentError, /NameID/)
    end

    it 'rejects EC public keys regardless of the certificate signature algorithm' do
      key             = OpenSSL::PKey::EC.generate('prime256v1')
      cert            = OpenSSL::X509::Certificate.new(idp.cert_pem)
      cert.public_key = key
      cert.sign(OpenSSL::PKey::RSA.new(2048), OpenSSL::Digest.new('SHA256'))
      expect(described_class.cert_problem(cert.to_pem)).to include('RSA public key')
      expect(described_class.cert_problem(cert.to_pem, allow_expired: true, allow_unsupported_key: true)).to be_nil
    end

    it 'caches parsing but rechecks both validity bounds on every call' do
      pem  = idp.cert_pem
      cert = OpenSSL::X509::Certificate.new(pem)
      described_class::CERTIFICATE_CACHE_LOCK.synchronize { described_class::CERTIFICATE_CACHE.clear }
      expect(OpenSSL::X509::Certificate).to receive(:new).with(pem.strip).once.and_call_original
      allow(Time).to receive(:now).and_return(cert.not_before - 1)
      expect(described_class.cert_problem(pem)).to include('not valid until')
      allow(Time).to receive(:now).and_return(cert.not_before + 1)
      expect(described_class.cert_problem(pem)).to be_nil
      allow(Time).to receive(:now).and_return(cert.not_after + 1)
      expect(described_class.cert_problem(pem)).to include('expired')
    end

    it 'keeps every platform option input live across certificate-cache hits' do
      env = {
        'SAML_IDP_SSO_SERVICE_URL' => trio[:idp_sso_service_url],
        'SAML_IDP_ENTITY_ID' => trio[:idp_entity_id],
        'SAML_IDP_CERT' => trio[:idp_cert],
        'SAML_UID_ATTRIBUTE' => 'subject',
        'SAML_ROUTE_NAME' => 'saml',
        'SAML_SP_ENTITY_ID' => '',
        'SAML_NAME_ID_FORMAT' => described_class::PERSISTENT_NAME_ID_FORMAT,
      }
      site = { 'site' => { 'host' => 'platform.example', 'ssl' => true } }
      session = { 'same_site' => 'none', 'secure' => true }
      allow(ENV).to receive(:fetch).and_wrap_original do |original, key, *args|
        env.key?(key) ? env[key] : original.call(key, *args)
      end
      allow(OT).to receive(:conf).and_return(site)
      allow(Onetime).to receive(:session_config).and_return(session)
      expect(described_class.platform_usable?).to be true
      env['SAML_UID_ATTRIBUTE'] = 'employee'
      env['SAML_ROUTE_NAME'] = 'company'
      env['SAML_NAME_ID_FORMAT'] = 'omit'
      site['site']['host'] = 'new.example'
      site['site']['ssl'] = false
      expect(described_class.platform_options).to include(uid_attribute: 'employee', name_identifier_format: nil,
        sp_entity_id: 'http://new.example/auth/sso/company/metadata', assertion_consumer_service_url: 'http://new.example/auth/sso/company/callback')
      env['SAML_SP_ENTITY_ID'] = 'urn:custom:sp'
      expect(described_class.platform_options[:sp_entity_id]).to eq('urn:custom:sp')
      env['SAML_IDP_ENTITY_ID'] = ''
      expect(described_class.platform_usable?).to be false
      env['SAML_IDP_ENTITY_ID'] = 'urn:new:idp'
      env['SAML_IDP_SSO_SERVICE_URL'] = 'http://insecure.example'
      expect(described_class.platform_usable?).to be false
      env['SAML_IDP_SSO_SERVICE_URL'] = 'https://new.idp.example/sso'
      expect(described_class.platform_options).to include(idp_entity_id: 'urn:new:idp', idp_sso_service_url: 'https://new.idp.example/sso')
      env['SAML_IDP_CERT'] = 'bad cert'
      expect(described_class.platform_usable?).to be false
      env['SAML_IDP_CERT'] = SamlSpec::TestIdp.new.cert_pem
      expect(described_class.platform_usable?).to be true
      session['same_site'] = 'strict'
      expect(described_class.platform_usable?).to be false
    end

    it 'rejects malformed callback policy including literal null and URL paths' do
      [nil, 'https://idp.example', ['null'], ['https://idp.example/'], ['http://idp.example'], ['https://*.example'], ['https://idp.example:443']].each do |value|
        expect(described_class.callback_origins_problem(value)).not_to be_nil
      end
      expect(described_class.callback_origins_problem(['https://idp.example:8443'])).to be_nil
    end
  end

  # The platform ACS URL is pinned to site.host, so this is the only host a
  # platform SAML sign-in can complete on. Narrower than
  # DomainStrategy.canonical_host? on purpose: a split deployment's secondary
  # canonical host is not the ACS host.
  describe '.platform_host?' do
    before do
      allow(OT).to receive(:conf).and_return({ 'site' => { 'host' => 'Secrets.Example.com:8443', 'ssl' => true } })
    end

    it 'matches site.host port- and case-insensitively' do
      expect(described_class.platform_host?('secrets.example.com')).to be true
      expect(described_class.platform_host?('SECRETS.example.com:8443')).to be true
      expect(described_class.platform_host?('secrets.example.com:443')).to be true
    end

    it 'does not match another host, a subdomain, or a parent' do
      expect(described_class.platform_host?('eu.secrets.example.com')).to be false
      expect(described_class.platform_host?('example.com')).to be false
      expect(described_class.platform_host?('tenant.example.net')).to be false
    end

    it 'is false for a blank or unparseable candidate' do
      expect(described_class.platform_host?(nil)).to be false
      expect(described_class.platform_host?('')).to be false
      expect(described_class.platform_host?('not a host')).to be false
    end

    it 'is false when site.host is not configured (there is no platform SAML host)' do
      allow(OT).to receive(:conf).and_return({ 'site' => { 'host' => '' } })

      expect(described_class.platform_host?('secrets.example.com')).to be false
    end

    it 'derives the same host the ACS URL is pinned to' do
      acs = described_class.platform_acs_url('saml')

      expect(acs).to eq('https://Secrets.Example.com:8443/auth/sso/saml/callback')
      expect(described_class.platform_host?(URI.parse(acs).host)).to be true
    end
  end
end
