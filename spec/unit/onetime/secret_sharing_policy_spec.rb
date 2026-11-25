# spec/unit/onetime/secret_sharing_policy_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/secret_lifetime_policy'
require 'onetime/secret_sharing_policy'
require File.join(Onetime::HOME, 'apps', 'web', 'billing', 'errors')

RSpec.describe Onetime::SecretSharingPolicy do
  subject(:policy) { described_class.new(organizations: [organization]) }

  let(:canonical_ceiling) { 604_800 }
  let(:policy_settings) { Onetime::Organization::SharingPolicy::DEFAULT }
  let(:organization) do
    instance_double(Onetime::Organization, objid: 'org-1', sharing_policy: policy_settings)
  end

  before do
    allow(Onetime::SecretLifetimePolicy).to receive(:canonical_guest_ceiling).and_return(canonical_ceiling)
  end

  describe '#max_ttl' do
    it 'uses the canonical guest ceiling for an organization whose plan cannot be resolved' do
      allow(organization).to receive(:limit_for).with('secret_lifetime')
        .and_raise(Billing::PlanCacheMissError.new(plan_id: 'retired_v1'))
      allow(OT).to receive(:le)

      expect(policy.max_ttl).to eq(canonical_ceiling)
      expect(policy.clamp_ttl(2_592_000, ceiling: 2_592_000)).to eq(canonical_ceiling)
      expect(OT).to have_received(:le).with(/Plan lifetime resolution failed/, hash_including(org_id: 'org-1')).twice
    end

    it 'keeps a narrower configured maximum when the plan cannot be resolved' do
      allow(organization).to receive(:sharing_policy).and_return(policy_settings.merge('max_ttl' => 3_600))
      allow(organization).to receive(:limit_for).and_raise(StandardError, 'plan unavailable')
      allow(OT).to receive(:le)

      expect(policy.max_ttl).to eq(3_600)
    end
  end

  describe '#recipient_allowed?' do
    # Domains go through SharingPolicy.normalize, as a saved policy does, so
    # the list holds comparison keys rather than the spelling an owner typed.
    def restricted_to(*domains)
      Onetime::Organization::SharingPolicy.normalize(
        Onetime::Organization::SharingPolicy::DEFAULT.merge(
          'recipient_email_mode' => 'restricted', 'recipient_email_domains' => domains,
        ),
      )
    end

    context 'when the policy lists example.com' do
      let(:policy_settings) { restricted_to('example.com') }

      it 'allows an exact match and ignores the case of either side' do
        expect(policy.recipient_allowed?('user@example.com')).to be(true)
        expect(policy.recipient_allowed?('USER@Example.COM')).to be(true)
      end

      it 'refuses an unlisted subdomain of the listed domain and a lookalike suffix' do
        expect(policy.recipient_allowed?('user@eng.example.com')).to be(false)
        expect(policy.recipient_allowed?('user@notexample.com')).to be(false)
        expect(policy.recipient_allowed?('user@example.com.evil.test')).to be(false)
      end

      # comparison_key keeps the trailing dot of an ASCII name, so the
      # address domain "example.com." has the key "example.com." and does
      # not equal the listed "example.com".
      it 'refuses an address domain with a trailing dot' do
        expect(policy.recipient_allowed?('user@example.com.')).to be(false)
      end

      it 'refuses an address with an empty domain, surrounding space or an invalid label' do
        expect(policy.recipient_allowed?('user@')).to be(false)
        expect(policy.recipient_allowed?('')).to be(false)
        expect(policy.recipient_allowed?('user@example.com ')).to be(false)
        expect(policy.recipient_allowed?('user@ex ample.com')).to be(false)
        expect(policy.recipient_allowed?('user@-bad.example.com')).to be(false)
        expect(policy.recipient_allowed?('user@ｅｘａｍｐｌｅ.com')).to be(false)
      end

      # The policy must not rely on the later deliverability check: a
      # Truemail allowed_domains setting skips the regex, and mail delivery
      # splits a comma list into separate destinations.
      it 'refuses anything that is not a single bare address in a listed domain' do
        ['a@b@example.com', '@example.com', 'example.com', 'user@evil.test,other@example.com',
         'user@evil.test;other@example.com', 'Evil <user@evil.test>, other@example.com',
         'a@example.com@evil.test', "user@evil.test\nother@example.com"].each do |address|
          expect(policy.recipient_allowed?(address)).to be(false), address
        end
        expect(policy.recipient_allowed?("o'brien+tag@example.com")).to be(true)
      end
    end

    context 'when the policy lists only the subdomain eng.example.com' do
      let(:policy_settings) { restricted_to('eng.example.com') }

      it 'allows the subdomain and refuses its parent and siblings' do
        expect(policy.recipient_allowed?('user@eng.example.com')).to be(true)
        expect(policy.recipient_allowed?('user@example.com')).to be(false)
        expect(policy.recipient_allowed?('user@ops.example.com')).to be(false)
        expect(policy.recipient_allowed?('user@a.eng.example.com')).to be(false)
      end
    end

    context 'when the policy lists a parent and a subdomain separately' do
      let(:policy_settings) { restricted_to('example.com', 'eng.example.com') }

      it 'allows both and nothing else below the parent' do
        expect(policy.recipient_allowed?('user@example.com')).to be(true)
        expect(policy.recipient_allowed?('user@eng.example.com')).to be(true)
        expect(policy.recipient_allowed?('user@ops.example.com')).to be(false)
      end
    end

    {
      'the Unicode form' => 'bücher.example',
      'an upper-case Unicode form' => 'BÜCHER.example',
      'the A-label form' => 'xn--bcher-kva.example',
    }.each do |description, listed|
      context "when the policy lists an IDN in #{description}" do
        let(:policy_settings) { restricted_to(listed) }

        it 'stores the A-label and matches an address in either form' do
          expect(policy_settings['recipient_email_domains']).to eq(['xn--bcher-kva.example'])
          expect(policy.recipient_allowed?('user@bücher.example')).to be(true)
          expect(policy.recipient_allowed?('user@BÜCHER.example')).to be(true)
          expect(policy.recipient_allowed?("user@bu\u0308cher.example")).to be(true)
          expect(policy.recipient_allowed?('user@xn--bcher-kva.example')).to be(true)
          expect(policy.recipient_allowed?('user@XN--BCHER-KVA.example')).to be(true)
          expect(policy.recipient_allowed?('user@bucher.example')).to be(false)
          expect(policy.recipient_allowed?('user@mail.bücher.example')).to be(false)
        end
      end
    end

    it 'matches a mixed-form subdomain against its listed A-label key, in both directions' do
      allow(organization).to receive(:sharing_policy).and_return(restricted_to('xn--bcher-kva.bücher.example'))
      expect(policy.recipient_allowed?('user@bücher.xn--bcher-kva.example')).to be(true)
      expect(policy.recipient_allowed?('user@xn--bcher-kva.xn--bcher-kva.example')).to be(true)
      expect(policy.recipient_allowed?('user@bücher.bücher.example')).to be(true)
      expect(policy.recipient_allowed?('user@bücher.example')).to be(false)
    end

    context 'when the policy disables recipient email' do
      let(:policy_settings) { Onetime::Organization::SharingPolicy::DEFAULT.merge('recipient_email_mode' => 'disabled') }

      it 'refuses every address' do
        %w[user@example.com user@eng.example.com user@bücher.example].each do |address|
          expect(policy.recipient_allowed?(address)).to be(false)
        end
      end
    end

    context 'when the policy is unrestricted' do
      it 'allows any address, leaving the address check to creation' do
        %w[user@example.com user@eng.example.com user@bücher.example user@unlisted.test].each do |address|
          expect(policy.recipient_allowed?(address)).to be(true)
        end
      end
    end

    it 'requires an address to satisfy every restricted organization' do
      first    = instance_double(Onetime::Organization, objid: 'org-a', sharing_policy: restricted_to('example.com', 'eng.example.com'))
      second   = instance_double(Onetime::Organization, objid: 'org-b', sharing_policy: restricted_to('eng.example.com'))
      combined = described_class.new(organizations: [first, second])
      expect(combined.recipient_allowed?('user@eng.example.com')).to be(true)
      expect(combined.recipient_allowed?('user@example.com')).to be(false)
    end
  end

  context 'with the strictest policy used for an unreadable stored policy' do
    let(:policy_settings) { Onetime::Organization::SharingPolicy::STRICTEST }

    before { allow(organization).to receive(:limit_for).with('secret_lifetime').and_return(2_592_000) }

    it 'refuses recipient email, requires a passphrase and holds the 60-second floor' do
      expect(policy.recipient_allowed?('person@example.com')).to be(false)
      expect(policy.passphrase_required?).to be(true)
      expect(policy.clamp_ttl(604_800, ceiling: 2_592_000)).to eq(60)
      expect(policy.clamp_ttl(1, ceiling: 2_592_000)).to eq(60)
    end
  end
end
