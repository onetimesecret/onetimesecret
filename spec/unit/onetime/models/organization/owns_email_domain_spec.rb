# spec/unit/onetime/models/organization/owns_email_domain_spec.rb
#
# frozen_string_literal: true
#
# Organization#verified_domains and #owns_email_domain?: the namespaces a
# tenant SSO flow may create accounts in (RISK-2026-10-10-01, #4734).
#
# The TXT challenge for a custom domain sits under the name as entered, so a
# passing check proves that name and the names below it, not the registrable
# domain above it. An organization proves an email namespace by adding it as a
# custom domain and completing the TXT check; the serving axis is irrelevant.

require 'spec_helper'

RSpec.describe 'Onetime::Organization#owns_email_domain?', :datastore do
  let(:suffix) { "#{Familia.now.to_i}-#{SecureRandom.hex(4)}" }
  let(:secrets_host) { "secrets-#{suffix}.acme-corp.example.com" }

  before do
    @domains = []
    @org     = Onetime::Organization.new(display_name: "Email Domains #{suffix}")
    @org.save
  end

  after do
    @domains.each do |domain|
      domain.destroy! if domain.exists?
    rescue StandardError => ex
      warn "[owns_email_domain spec] domain cleanup failed: #{ex.class}: #{ex.message}"
    end
    @org.destroy! if @org.exists?
  end

  # A persisted custom domain listed in the org's domains set, with its
  # ownership axis in the given state. No serving-axis fields are touched.
  def add_domain(display_domain, verified: true, override: false)
    domain                      = Onetime::CustomDomain.parse(display_domain, @org.objid)
    domain.ownership_verified   = verified
    domain.verified_by_override = override
    domain.save
    @org.add_domain(domain)
    @domains << domain
    domain
  end

  describe '#verified_domains' do
    it 'lists the custom domains whose ownership is accepted and no other' do
      proven   = add_domain(secrets_host)
      pending  = add_domain("pending-#{suffix}.acme-corp.example.com", verified: false)
      override = add_domain("override-#{suffix}.acme-corp.example.com", override: true)

      expect(@org.verified_domains.map(&:identifier))
        .to contain_exactly(proven.identifier, override.identifier)
      expect(@org.verified_domains.map(&:identifier)).not_to include(pending.identifier)
    end

    it 'is empty for an organization without custom domains' do
      expect(@org.verified_domains).to eq([])
    end
  end

  describe '#owns_email_domain?' do
    before { add_domain(secrets_host) }

    it 'accepts the verified custom domain itself' do
      expect(@org.owns_email_domain?(secrets_host)).to be(true)
    end

    it 'accepts a name below the verified custom domain' do
      expect(@org.owns_email_domain?("mail.#{secrets_host}")).to be(true)
    end

    it 'compares case-insensitively' do
      expect(@org.owns_email_domain?(secrets_host.upcase)).to be(true)
    end

    it 'does not extend the proof upward to the registrable domain' do
      # The TXT record for secrets-<x>.acme-corp.example.com proves control of
      # that name; it says nothing about who answers mail at acme-corp.example.com.
      expect(@org.owns_email_domain?('acme-corp.example.com')).to be(false)
      expect(@org.owns_email_domain?('example.com')).to be(false)
    end

    it 'does not accept a sibling that merely ends in the same characters' do
      expect(@org.owns_email_domain?("not#{secrets_host}")).to be(false)
      expect(@org.owns_email_domain?("other-#{suffix}.acme-corp.example.com")).to be(false)
    end

    it 'does not accept a domain outside the organization' do
      expect(@org.owns_email_domain?('unrelated.example.org')).to be(false)
    end

    it 'does not count a custom domain whose ownership is not yet accepted' do
      pending = add_domain("pending-#{suffix}.acme-corp.example.com", verified: false)

      expect(@org.owns_email_domain?(pending.display_domain)).to be(false)
    end

    it 'counts a custom domain accepted by Colonel override' do
      forced = add_domain("override-#{suffix}.acme-corp.example.com", override: true)

      expect(@org.owns_email_domain?(forced.display_domain)).to be(true)
    end

    it 'stops counting a domain once its ownership is withdrawn' do
      domain                    = @domains.first
      domain.ownership_verified = false
      domain.save

      expect(@org.owns_email_domain?(secrets_host)).to be(false)
    end

    it 'treats the Unicode and A-label spellings of a verified domain as one name' do
      unicode = add_domain("bücher-#{suffix}.acme-corp.example.com")
      a_label = Onetime::DomainValidation::AsciiHostname.call(unicode.display_domain)

      expect(a_label).to start_with('xn--')
      expect(@org.owns_email_domain?(a_label)).to be(true)
      expect(@org.owns_email_domain?(unicode.display_domain)).to be(true)
    end

    it 'is false for a blank or absent domain' do
      expect(@org.owns_email_domain?('')).to be(false)
      expect(@org.owns_email_domain?(nil)).to be(false)
      expect(@org.owns_email_domain?('   ')).to be(false)
    end

    it 'judges against a caller-supplied set instead of loading one' do
      stranger = Onetime::CustomDomain.parse("stranger-#{suffix}.example.net", @org.objid)
      stranger.ownership_verified = true

      expect(@org.owns_email_domain?(stranger.display_domain, domains: [stranger])).to be(true)
      expect(@org.owns_email_domain?(secrets_host, domains: [stranger])).to be(false)
    end
  end
end
