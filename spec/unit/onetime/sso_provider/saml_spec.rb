# spec/unit/onetime/sso_provider/saml_spec.rb
#
# frozen_string_literal: true

# Onetime::SsoProvider::Saml — the per-value rules the platform env, the
# tenant model and the tenant API all share (#4450).
#
#   .sso_url_problem         one rule for the IdP SSO service URL, including
#                            the CSP-origin funnel (AuthConfig.origin_from_url)
#   .session_cookie_problem  the SameSite=None + Secure prerequisite as code,
#                            shared by .platform_options (provider skipped),
#                            the placeholder boot warning and the API refusal
#   .platform_host?          the host the platform ACS is pinned to at boot
#                            (site.host); descriptive only, since platform
#                            fallback on a verified custom domain rebinds the
#                            ACS per request (OmniAuthTenant.bind_platform_
#                            fallback_acs)
#
# RUN (always via the lane runner — see AGENTS.md):
#   tests/lanes/run unit --only spec/unit/onetime/sso_provider/saml_spec.rb

require 'spec_helper'
require_relative '../../../../lib/onetime/sso_provider/saml'

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

    it 'names both settings and the consequence for the shipped default (lax)' do
      problem = described_class.session_cookie_problem('same_site' => 'lax', 'secure' => true)

      expect(problem).to include("same_site is 'lax'", 'secure is true', 'same_site: none with secure: true',
        'saml_no_pending_request')
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
      expect(described_class.session_cookie_problem(Onetime::Initializers::SESSION_DEFAULTS)).to include("'lax'")
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
