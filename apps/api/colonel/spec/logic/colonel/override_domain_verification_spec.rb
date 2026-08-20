# apps/api/colonel/spec/logic/colonel/override_domain_verification_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

RSpec.describe ColonelAPI::Logic::Colonel::OverrideDomainVerification do
  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel', role: 'colonel',
      verified?: true, anonymous?: false)
  end

  let(:strategy_result) do
    double('StrategyResult', session: {}, user: colonel,
      auth_method: 'sessionauth', metadata: {})
  end

  # Mutable stand-in for Onetime::CustomDomain so mutation (or the absence
  # of mutation) is directly observable without a datastore.
  let(:domain_class) do
    Class.new do
      attr_accessor :verified, :resolving, :updated

      def initialize(verified:, resolving:)
        @verified  = verified
        @resolving = resolving
        @updated   = 0
      end

      def atomic_write(**)
        yield
        true
      end

      def domainid = 'cd_internal'
      def extid = 'cd_target'
      def display_domain = 'secrets.example.com'
      def verification_state = @verified ? :verified : :unverified
      def ready? = !!(@verified && @resolving)
    end
  end

  let(:custom_domain) { domain_class.new(verified: false, resolving: false) }

  def logic_for(params = {})
    described_class.new(strategy_result, { 'extid' => 'cd_target' }.merge(params))
  end

  def run(params = {})
    logic = logic_for(params)
    logic.raise_concerns
    logic.process
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(Onetime::CustomDomain).to receive(:find_by_extid).and_return(custom_domain)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
  end

  describe 'success_data change indicators' do
    it 'reports both flags changed when overrides flip them' do
      data = run('verified' => 'true', 'resolving' => 'true')

      expect(data[:details]).to include(
        previous_verified: false,
        previous_resolving: false,
        current_verified: true,
        current_resolving: true,
        verified_changed: true,
        resolving_changed: true,
      )
      expect(custom_domain.verified).to be(true)
      expect(custom_domain.resolving).to be(true)
    end

    it 'reports no change for a no-op override and an omitted flag' do
      already_verified = domain_class.new(verified: true, resolving: false)
      allow(Onetime::CustomDomain).to receive(:find_by_extid).and_return(already_verified)

      data = run('verified' => 'true')

      expect(data[:details]).to include(
        previous_verified: true,
        current_verified: true,
        verified_changed: false,
        previous_resolving: false,
        current_resolving: false,
        resolving_changed: false,
      )
      expect(already_verified.resolving).to be(false)
    end

    it 'reports a change when clearing a previously-set flag' do
      was_verified = domain_class.new(verified: true, resolving: true)
      allow(Onetime::CustomDomain).to receive(:find_by_extid).and_return(was_verified)

      data = run('verified' => 'false')

      expect(data[:details]).to include(
        previous_verified: true,
        current_verified: false,
        verified_changed: true,
        resolving_changed: false,
      )
      expect(was_verified.verified).to be(false)
      expect(was_verified.resolving).to be(true)
    end
  end

  describe 'boolean param parsing' do
    %w[true 1 yes on TRUE Yes].each do |spelling|
      it "parses #{spelling.inspect} as true" do
        expect(logic_for('verified' => spelling).verified_param).to be(true)
      end
    end

    %w[false 0 no off FALSE No].each do |spelling|
      it "parses #{spelling.inspect} as false" do
        expect(logic_for('verified' => spelling).verified_param).to be(false)
      end
    end

    it 'treats a blank param as nil (unchanged) when the other flag is set' do
      logic = logic_for('verified' => 'true', 'resolving' => '   ')

      expect(logic.verified_param).to be(true)
      expect(logic.resolving_param).to be_nil
    end

    it 'rejects an unrecognized value without touching the domain' do
      expect { logic_for('verified' => 'maybe') }
        .to raise_error(Onetime::FormError, /Invalid boolean value for verified: "maybe"/)

      expect(Onetime::CustomDomain).not_to have_received(:find_by_extid)
      expect(custom_domain.verified).to be(false)
      expect(custom_domain.resolving).to be(false)
    end

    it 'rejects an unrecognized resolving value naming the resolving field' do
      expect { logic_for('resolving' => 'sometimes') }
        .to raise_error(Onetime::FormError, /Invalid boolean value for resolving/)
    end

    it 'requires at least one flag when both params are absent or blank' do
      expect { logic_for('verified' => '', 'resolving' => nil) }
        .to raise_error(Onetime::FormError, /At least one of verified or resolving/)
    end
  end
end
