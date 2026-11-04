# spec/unit/onetime/models/organization/owns_email_domain_spec.rb
#
# frozen_string_literal: true
#
# Organization#verified_domains, #owns_email_domain? and
# #owns_email_domain_through?: the namespaces a tenant SSO flow may create
# accounts in (RISK-2026-10-10-01, #4734).
#
# The TXT challenge for a custom domain sits under the name as entered, so a
# passing check proves that name and the names below it, not the registrable
# domain above it. An organization proves an email namespace by adding it as a
# custom domain and completing the TXT check; the serving axis is irrelevant.
#
# A domain counts only when its ownership rests on evidence
# (CustomDomain#ownership_proven?): a Colonel override, or, under a
# validation strategy that checks the TXT record, ownership_verified with a
# passing check on record (verified_confirmed_at). The test install runs
# passthrough, whose verify call sets ownership_verified without a DNS lookup
# and records no pass, so the matching examples run under caddy_on_demand,
# set in OT.conf.

require 'spec_helper'
require 'onetime/operations/verify_domain'
require 'onetime/domain_validation/passthrough_strategy'

RSpec.describe 'Onetime::Organization#owns_email_domain?', :datastore do
  let(:suffix) { "#{Familia.now.to_i}-#{SecureRandom.hex(4)}" }
  let(:secrets_host) { "secrets-#{suffix}.acme-corp.example.com" }

  before do
    @domains = []
    @org     = Onetime::Organization.new(display_name: "Email Domains #{suffix}")
    @org.save
  end

  # features.domains settings for this example only, on a copy of OT.conf.
  # CustomDomain.ownership_proof_required? decides again whenever the
  # strategy setting differs, so nothing has to be reset.
  def configure_domains(**overrides)
    conf    = YAML.load(YAML.dump(OT.conf))
    domains = ((conf['features'] ||= {})['domains'] ||= {})
    overrides.each { |key, value| domains[key.to_s] = value }
    allow(OT).to receive(:conf).and_return(conf)
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
  # A verified domain without an override has a TXT pass on record (what a
  # passing check under a TXT strategy leaves) unless `confirmed: false`
  # (what a passthrough verify call leaves).
  def add_domain(display_domain, verified: true, override: false, confirmed: verified && !override)
    domain                       = Onetime::CustomDomain.parse(display_domain, @org.objid)
    domain.ownership_verified    = verified
    domain.verified_by_override  = override
    domain.verified_confirmed_at = Familia.now.to_i - 3600 if confirmed
    domain.save
    @org.add_domain(domain)
    @domains << domain
    domain
  end

  context 'under a validation strategy that checks the TXT record (caddy_on_demand)' do
    before { configure_domains(validation_strategy: 'caddy_on_demand') }

    it 'is the configuration the examples below assume' do
      expect(Onetime::CustomDomain.ownership_proof_required?).to be(true)
    end

    describe '#verified_domains' do
      it 'lists the custom domains whose ownership is proven and no other' do
        proven   = add_domain(secrets_host)
        pending  = add_domain("pending-#{suffix}.acme-corp.example.com", verified: false)
        override = add_domain("override-#{suffix}.acme-corp.example.com", override: true)
        # Verified with no TXT pass on record: verified under passthrough
        # before the strategy changed, or before v0.26.14.
        legacy   = add_domain("legacy-#{suffix}.acme-corp.example.com", confirmed: false)

        expect(@org.verified_domains.map(&:identifier))
          .to contain_exactly(proven.identifier, override.identifier)
        expect(@org.verified_domains.map(&:identifier)).not_to include(pending.identifier, legacy.identifier)
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

      it 'does not count a verified custom domain with no TXT pass on record' do
        legacy = add_domain("legacy-#{suffix}.acme-corp.example.com", confirmed: false)

        expect(legacy.ownership_verified).to be(true)
        expect(legacy.verified_confirmed_at).to be_nil
        expect(@org.owns_email_domain?(legacy.display_domain)).to be(false)
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
        stranger.ownership_verified    = true
        stranger.verified_confirmed_at = Familia.now.to_i

        expect(@org.owns_email_domain?(stranger.display_domain, domains: [stranger])).to be(true)
        expect(@org.owns_email_domain?(secrets_host, domains: [stranger])).to be(false)
      end
    end

    # The flow's own domain is judged from the record the caller already has;
    # the organization's other domain records (list_domains, behind
    # verified_domains) are loaded only when that domain does not settle the
    # question. The answer is the one any? over proven_email_domains_through
    # gives, whichever path is taken.
    describe '#owns_email_domain_through?' do
      let(:own_host) { "sso-#{suffix}.acme-corp.example.com" }

      it "accepts an address at the flow's own proven domain without loading the domain list" do
        own = add_domain(own_host)
        expect(@org).not_to receive(:list_domains)

        expect(@org.owns_email_domain_through?(own, own_host)).to be(true)
      end

      it "accepts an address below the flow's own proven domain without loading the domain list" do
        own = add_domain(own_host)
        expect(@org).not_to receive(:list_domains)

        expect(@org.owns_email_domain_through?(own, "mail.#{own_host}")).to be(true)
      end

      it 'is false for a blank or absent address without loading anything' do
        own = add_domain(own_host)
        expect(@org).not_to receive(:list_domains)

        expect(@org.owns_email_domain_through?(own, '')).to be(false)
        expect(@org.owns_email_domain_through?(own, nil)).to be(false)
        expect(@org.owns_email_domain_through?(own, '   ')).to be(false)
      end

      context "when the flow's own domain is not proven" do
        it 'falls through to the verified domains, which cover an address at it when a proven domain lies above' do
          add_domain(secrets_host)
          below = add_domain("sso-#{suffix}.#{secrets_host}", verified: false)
          expect(@org).to receive(:list_domains).once.and_call_original

          expect(below.ownership_proven?).to be(false)
          expect(@org.owns_email_domain_through?(below, below.display_domain)).to be(true)
        end

        it 'falls through to the verified domains, which do not cover an address at it otherwise' do
          add_domain(secrets_host)
          pending = add_domain("pending-#{suffix}.acme-corp.example.com", verified: false)
          expect(@org).to receive(:list_domains).once.and_call_original

          expect(pending.ownership_proven?).to be(false)
          expect(@org.owns_email_domain_through?(pending, pending.display_domain)).to be(false)
        end
      end

      context "for an address outside the flow's own domain" do
        it 'falls through to the verified domains and accepts an address another proven domain covers' do
          own   = add_domain(own_host)
          other = add_domain(secrets_host)
          expect(@org).to receive(:list_domains).once.and_call_original

          expect(@org.owns_email_domain_through?(own, "mail.#{other.display_domain}")).to be(true)
        end

        it 'falls through to the verified domains and refuses an address no proven domain covers' do
          own = add_domain(own_host)
          add_domain("pending-#{suffix}.acme-corp.example.com", verified: false)
          expect(@org).to receive(:list_domains).twice.and_call_original

          expect(@org.owns_email_domain_through?(own, 'unrelated.example.org')).to be(false)
          expect(@org.owns_email_domain_through?(own, "pending-#{suffix}.acme-corp.example.com")).to be(false)
        end
      end
    end
  end

  context 'under a validation strategy that makes no TXT check (passthrough)' do
    let(:passthrough) { Onetime::DomainValidation::PassthroughStrategy.new({}) }

    before do
      configure_domains(validation_strategy: 'passthrough')
      # The unit lane boots without the pool VerifyDomain pins its writes
      # to; hand it a plain client (see verify_domain_orphan_spec).
      allow(Onetime).to receive(:with_pinned_dbclient) { |&block| block.call(Familia.dbclient) }
    end

    def verify_with_passthrough(domain)
      result = Onetime::Operations::VerifyDomain.new(domain: domain, strategy: passthrough).call
      expect(result.persisted).to be(true)
      Onetime::CustomDomain.find_by_identifier(domain.identifier)
    end

    it 'is the configuration the examples below assume' do
      expect(Onetime::CustomDomain.ownership_proof_required?).to be(false)
    end

    # The organization registers any name and the verify call passes it
    # without a lookup (RISK-2026-10-10-01 on a passthrough install).
    it 'does not count a domain the verify call passed without looking at DNS' do
      victim = verify_with_passthrough(add_domain("victim-#{suffix}.example.com", verified: false))

      expect(victim.ownership_verified).to be(true)
      expect(victim.verified_by_override).not_to be(true)
      expect(victim.ownership_proven?).to be(false)
      expect(@org.verified_domains).to eq([])
      expect(@org.owns_email_domain?(victim.display_domain)).to be(false)
      expect(@org.owns_email_domain_through?(victim, "mail.#{victim.display_domain}")).to be(false)
      expect(@org.proven_email_domains_through(victim)).to eq([])
    end

    it 'does not count ownership_verified alone, however it was set' do
      verified = add_domain(secrets_host, confirmed: false)
      # A TXT pass recorded under an earlier strategy does not count here either.
      earlier  = add_domain("earlier-#{suffix}.acme-corp.example.com", confirmed: true)

      expect(@org.verified_domains).to eq([])
      expect(@org.owns_email_domain?(secrets_host)).to be(false)
      expect(@org.owns_email_domain?(earlier.display_domain)).to be(false)
      expect(@org.owns_email_domain_through?(verified, secrets_host)).to be(false)
    end

    it 'counts a domain accepted by Colonel override' do
      forced = add_domain("override-#{suffix}.acme-corp.example.com", override: true)

      expect(forced.ownership_proven?).to be(true)
      expect(@org.verified_domains.map(&:identifier)).to eq([forced.identifier])
      expect(@org.owns_email_domain?(forced.display_domain)).to be(true)
      expect(@org.owns_email_domain?("mail.#{forced.display_domain}")).to be(true)
      expect(@org.owns_email_domain_through?(forced, forced.display_domain)).to be(true)
      expect(@org.proven_email_domains_through(forced).map(&:identifier)).to eq([forced.identifier])
    end

    it 'does not count an override whose ownership was withdrawn' do
      forced = add_domain("override-#{suffix}.acme-corp.example.com", verified: false, override: true)

      expect(forced.ownership_proven?).to be(false)
      expect(@org.verified_domains).to eq([])
      expect(@org.owns_email_domain_through?(forced, forced.display_domain)).to be(false)
    end

    it 'keeps an overridden domain proven through a passthrough verify call' do
      forced = verify_with_passthrough(add_domain("override-#{suffix}.acme-corp.example.com", override: true))

      expect(forced.ownership_verified).to be(true)
      expect(forced.verified_by_override).to be(true)
      expect(forced.verified_confirmed_at).to be_nil
      expect(@org.verified_domains.map(&:identifier)).to eq([forced.identifier])
      expect(@org.owns_email_domain?(forced.display_domain)).to be(true)
      expect(@org.owns_email_domain_through?(forced, forced.display_domain)).to be(true)
    end
  end
end
