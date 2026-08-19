# spec/unit/onetime/models/organization/destroy_domain_guard_spec.rb
#
# frozen_string_literal: true

# Unit tests for the Organization#destroy! domain guard and the
# Organization#archive! domain policy.
#
# destroy! refuses when the `domains` sorted set is non-empty (existing
# behavior) OR when the CustomDomain.owners class hashkey still attributes a
# live domain to the org even though the sorted set has lost it (index
# drift). Without the second check, drift lets the guard pass and the org is
# destroyed while domain records still reference it (dangling org_id).
# archive! stays deliberately permissive (SSO login-path self-heal callers);
# it only warns.
#
# Real datastore (Valkey on 2163, see spec/config.test.yaml): the guard is
# about index state, so it is exercised against real keys. Every object and
# manual index entry created here is registered and removed in `after`. It
# NEVER flushes — the test datastore is shared.
#
# Run: bundle exec rspec spec/unit/onetime/models/organization/destroy_domain_guard_spec.rb

require 'spec_helper'

RSpec.describe 'Onetime::Organization destroy!/archive! domain guard', :datastore do
  let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

  before do
    @orgs         = []
    @domains      = []
    @owners_keys  = [] # manual CustomDomain.owners entries to purge

    @org = track_org(Onetime::Organization.new(display_name: "Destroy Guard #{suffix}"))
    @org.save
  end

  after do
    @owners_keys.each do |key|
      Onetime::CustomDomain.owners.remove(key)
    rescue StandardError => ex
      warn "[destroy guard spec] owners cleanup failed: #{ex.class}: #{ex.message}"
    end
    @domains.each do |domain|
      domain.destroy! if domain.exists?
    rescue StandardError => ex
      warn "[destroy guard spec] domain cleanup failed: #{ex.class}: #{ex.message}"
    end
    @orgs.each do |org|
      org.destroy! if org.exists?
    rescue StandardError => ex
      warn "[destroy guard spec] org cleanup failed: #{ex.class}: #{ex.message}"
    end
  end

  def track_org(org)
    @orgs << org
    org
  end

  # Build and persist a real CustomDomain record pointing at the org via
  # org_id, WITHOUT adding it to the org's domains sorted set or the owners
  # hashkey — callers opt in to each index to stage the exact state under test.
  def create_domain(display_domain)
    domain = Onetime::CustomDomain.parse(display_domain, @org.objid)
    domain.save
    @domains << domain
    domain
  end

  def put_owners_entry(key, org_id)
    Onetime::CustomDomain.owners.put(key, org_id)
    @owners_keys << key
  end

  describe '#destroy!' do
    context 'when the domains sorted set is non-empty (existing behavior)' do
      it 'refuses with the remove-all-domains message' do
        domain = create_domain("listed-#{suffix}.example.com")
        domain.add_to_organization_domains(@org, Familia.now.to_f)

        expect { @org.destroy! }.to raise_error(
          Onetime::Problem, 'Cannot delete organization with domains. Remove all domains first.'
        )
        expect(@org.exists?).to be(true)
      end
    end

    context 'when the set is empty but owners attributes a live domain to the org (drift)' do
      it 'refuses and names the drifted domain in the error' do
        domain = create_domain("drifted-#{suffix}.example.com")
        put_owners_entry(domain.to_s, @org.objid)

        expect(@org.domain_count).to eq(0) # precondition: the set has drifted

        expect { @org.destroy! }.to raise_error(Onetime::Problem) do |error|
          expect(error.message).to include("drifted-#{suffix}.example.com")
          expect(error.message).to include('not visible in the organization domain list')
          expect(error.message).to include('bin/ots domains doctor')
        end
        expect(@org.exists?).to be(true)
      end
    end

    context 'when neither source shows domains' do
      it 'destroys the org and removes it from Organization.instances' do
        expect(Onetime::Organization.in_instances?(@org.objid)).to be(true)

        @org.destroy!

        expect(@org.exists?).to be(false)
        # Familia destroy! calls remove_from_instances! — assert the registry
        # entry is gone so a regression there is caught here.
        expect(Onetime::Organization.in_instances?(@org.objid)).to be(false)
      end
    end

    context 'when owners has a stale entry whose record no longer loads' do
      it 'ignores the stale entry and destroys the org' do
        stale_key = "stale_domain_objid_#{suffix}"
        put_owners_entry(stale_key, @org.objid)

        expect(@org.unlisted_owned_domains).to be_empty
        expect { @org.destroy! }.not_to raise_error
        expect(@org.exists?).to be(false)
      end
    end
  end

  describe '#unlisted_owned_domains' do
    it 'excludes domains that are present in the domains sorted set' do
      domain = create_domain("both-indexes-#{suffix}.example.com")
      domain.add_to_organization_domains(@org, Familia.now.to_f)
      put_owners_entry(domain.to_s, @org.objid)

      expect(@org.unlisted_owned_domains).to be_empty
    end

    it 'excludes owners entries that belong to a different org' do
      other_org = track_org(Onetime::Organization.new(display_name: "Other #{suffix}"))
      other_org.save
      domain = create_domain("other-org-#{suffix}.example.com")
      put_owners_entry(domain.to_s, other_org.objid)

      expect(@org.unlisted_owned_domains).to be_empty
    end

    it 'returns loaded CustomDomain records for drifted entries' do
      domain = create_domain("loadable-#{suffix}.example.com")
      put_owners_entry(domain.to_s, @org.objid)

      result = @org.unlisted_owned_domains
      expect(result.map(&:display_domain)).to eq(["loadable-#{suffix}.example.com"])
      expect(result.first).to be_a(Onetime::CustomDomain)
    end
  end

  describe '#archive!' do
    it 'still archives when domains exist (permissive policy) and warns' do
      domain = create_domain("archived-#{suffix}.example.com")
      domain.add_to_organization_domains(@org, Familia.now.to_f)

      allow(OT).to receive(:lw)

      expect { @org.archive!('spec: permissive archive') }.not_to raise_error

      expect(@org.archived?).to be(true)
      expect(OT).to have_received(:lw).with(a_string_including(@org.extid, 'doctor check #9'))
    end

    it 'does not warn when there are no domains' do
      allow(OT).to receive(:lw)

      @org.archive!

      expect(@org.archived?).to be(true)
      expect(OT).not_to have_received(:lw)
    end
  end
end
