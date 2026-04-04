# apps/api/v2/spec/logic/secrets/base_secret_action_spec.rb
#
# frozen_string_literal: true

# ============================================================================
# Config Path Bug Tests (TDD Red Phase)
#
# These tests demonstrate that process_ttl reads secret_options from the
# WRONG config path. It does:
#
#   OT.conf.fetch('secret_options', { hardcoded fallback })
#
# But secret_options is nested under 'site' in config. The correct path
# (used by validate_passphrase in the same file) is:
#
#   OT.conf.dig('site', 'secret_options')
#
# As a result, process_ttl ALWAYS uses the hardcoded fallback values:
#   default_ttl: 604800 (7 days)
#   ttl_options: [60, 3600, 86400, 604800]
#
# Instead of the test config values (spec/config.test.yaml):
#   default_ttl: 43200 (12 hours)
#   ttl_options: [1800, 43200, 604800]
#
# These tests should FAIL against the current code and PASS after the fix.
# ============================================================================

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative File.join(Onetime::HOME, 'spec', 'support', 'model_test_helper.rb')

RSpec.describe 'V2 BaseSecretAction config path bug' do
  using Familia::Refinements::TimeLiterals

  # Subclass that implements the required abstract method
  class V2ConfigTestAction < V2::Logic::Secrets::BaseSecretAction
    def process_secret
      @kind = :test
      @secret_value = 'test_secret'
    end
  end

  # Stub organization_instances with a non-empty array so CreateDefaultWorkspace
  # sees the customer already has an org and skips creation (these tests are
  # about TTL config, not workspace creation).
  let(:customer) {
    double('Customer',
      anonymous?: false,
      custid: 'cust123',
      objid: 'obj123',
      planid: 'anonymous',
      email: 'cust123@example.com',
      organization_instances: [:existing_org])
  }

  let(:session) {
    double('Session',
      anonymous?: false,
      custid: 'cust123',
      identifier: 'sess123')
  }

  # V2 Logic::Base takes a strategy_result, not raw session/customer
  let(:strategy_result) {
    double('StrategyResult',
      session: session,
      user: customer,
      metadata: { organization_context: {} })
  }

  # V2 uses nested params: params['secret'] contains the secret fields
  let(:base_params) {
    {
      'secret' => {
        'recipient'    => [],
        'share_domain' => '',
      },
    }
  }

  subject { V2ConfigTestAction.new(strategy_result, base_params) }

  before(:all) do
    OT.boot!(:test)
  end

  before do
    allow(Truemail).to receive(:validate).and_return(
      double('Validator', result: double('Result', valid?: true), as_json: '{}'),
    )
  end

  describe '#process_ttl config path' do
    it 'reads default_ttl from site.secret_options in config (43200), not the hardcoded fallback (604800)' do
      # Verify the config actually has the value we expect at the correct path
      configured_default_ttl = OT.conf.dig('site', 'secret_options', 'default_ttl')
      expect(configured_default_ttl).to eq(43200), "Precondition: config.test.yaml should define site.secret_options.default_ttl as 43200"

      # Now test that process_ttl actually uses that config value when no TTL is provided
      subject.instance_variable_set(:@payload, {})
      subject.send(:process_ttl)

      expect(subject.ttl).to eq(43200),
        "Expected default_ttl=43200 from config, got #{subject.ttl}. " \
        "Bug: process_ttl reads OT.conf.fetch('secret_options') (root level) " \
        "instead of OT.conf.dig('site', 'secret_options')"
    end

    it 'reads ttl_options from site.secret_options in config, not the hardcoded fallback' do
      # The test config defines: ttl_options: '1800 43200 604800'
      # After OT::Config.after_load parses it, this becomes [1800, 43200, 604800]
      #
      # The hardcoded V2 fallback is [60, 3600, 86400, 604800]
      # So the arrays differ in both values and length.
      configured_options = OT.conf.dig('site', 'secret_options', 'ttl_options')
      expect(configured_options).to be_an(Array), "Precondition: after_load should parse ttl_options string into an array"
      expect(configured_options).to include(43200), "Precondition: ttl_options should include 43200"

      # The real differentiator: config min_ttl is 1800, but V2 hardcoded
      # fallback min is 60 (1.minute). A TTL of 120 (2 minutes) should be
      # clamped UP to 1800 by config, but the hardcoded fallback would allow
      # it through (since 120 > 60).
      subject.instance_variable_set(:@payload, { 'ttl' => '120' })
      subject.send(:process_ttl)

      expect(subject.ttl).to eq(1800),
        "Expected TTL=120 to be clamped to config min_ttl=1800, " \
        "got #{subject.ttl}. Bug: hardcoded fallback has min_ttl=60, " \
        "so 120 passes through unclamped."
    end

    it 'uses config default_ttl (43200) when TTL param is nil' do
      subject.instance_variable_set(:@payload, { 'ttl' => nil })
      subject.send(:process_ttl)

      expect(subject.ttl).to eq(43200),
        "Expected nil TTL to default to config's 43200, got #{subject.ttl}. " \
        "Bug: falls through to hardcoded 604800 because it reads from wrong config path."
    end

    it 'uses config default_ttl (43200) when TTL key is absent from payload' do
      subject.instance_variable_set(:@payload, {})
      subject.send(:process_ttl)

      expect(subject.ttl).to eq(43200),
        "Expected absent TTL to default to config's 43200, got #{subject.ttl}. " \
        "Bug: falls through to hardcoded 604800 because it reads from wrong config path."
    end

    it 'enforces config min_ttl (1800) not hardcoded min_ttl (60)' do
      # V2 hardcoded fallback: ttl_options.min = 60 (1.minute)
      # Config value: ttl_options.min = 1800 (30 minutes)
      #
      # A TTL of 300 (5 minutes) is above the hardcoded min but below config min.
      subject.instance_variable_set(:@payload, { 'ttl' => '300' })
      subject.send(:process_ttl)

      expect(subject.ttl).to eq(1800),
        "Expected TTL=300 to be clamped to config min=1800, got #{subject.ttl}. " \
        "Bug: hardcoded fallback min is 60, so values between 60-1800 pass through."
    end
  end
end
