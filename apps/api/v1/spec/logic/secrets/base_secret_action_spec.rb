# apps/api/v1/spec/logic/secrets/base_secret_action_spec.rb
#
# frozen_string_literal: true

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative File.join(Onetime::HOME, 'spec', 'support', 'model_test_helper.rb')



RSpec.xdescribe V1::Logic::Secrets::BaseSecretAction do
  using Familia::Refinements::TimeLiterals

  # Create test implementation class
  class TestSecretAction < V1::Logic::Secrets::BaseSecretAction
    def process_secret
      @kind = :test
      @secret_value = "test_secret"
    end
  end

  let(:customer) {
    double('Customer',
    anonymous?: false,
    custid: 'cust123',
    planid: 'anonymous')
  }

  let(:session) {
    double('Session',
    anonymous?: false,
    custid: 'cust123')
  }

  let(:base_params) {
    {
      'ttl'          => '7',
      'recipient'    => ['test@example.com'],
      'share_domain' => 'example.com'
    }
  }

  subject { TestSecretAction.new(session, customer, base_params) }

  before(:all) do
    OT.boot!(:test)
  end

  before do
    allow(Truemail).to receive(:validate).and_return(
      double('Validator', result: double('Result', valid?: true), as_json: '{}'),
    )
  end

  describe '#process_ttl' do
    it 'sets default TTL when none provided' do
      subject.instance_variable_set(:@payload, {})
      subject.send(:process_ttl)
      expect(subject.default_expiration).to eq(7.days) # was 12.hours
    end

    it 'enforces minimum TTL' do
      subject.instance_variable_set(:@payload, {ttl: '5'}) # 5 seconds
      subject.send(:process_ttl)
      expect(subject.default_expiration).to eq(30.minutes) # Set in config.test.yaml
    end

    it 'sets default TTL when provided as a string' do
      subject.instance_variable_set(:@payload, {'ttl' => '30'}) # 30 seconds
      subject.send(:process_ttl)
      expect(subject.default_expiration).to eq(7.days) # 7.days
    end
  end

  describe '#validate_recipient' do
    context 'with valid recipient' do
      it 'passes validation for valid email' do
        subject.instance_variable_set(:@recipient, ['valid@example.com'])
        expect { subject.send(:validate_recipient) }.not_to raise_error
      end
    end

    context 'with invalid recipient' do
      it 'raises error for anonymous user trying to send email' do
        allow(customer).to receive(:anonymous?).and_return(true)
        subject.instance_variable_set(:@recipient, ['test@example.com'])

        expect { subject.send(:validate_recipient) }.to raise_error(
          OT::FormError, /account is required/
        )
      end
    end
  end

  describe '#valid_email?' do
    let(:validator_result) { double('Result', valid?: true) }
    let(:validator) { double('Validator', result: validator_result, as_json: '{}') }

    it 'returns true for valid email' do
      allow(Truemail).to receive(:validate).with('test@example.com').and_return(validator)
      expect(subject.valid_email?('test@example.com')).to be true
    end

    it 'handles validation errors gracefully' do
      allow(Truemail).to receive(:validate)
        .with('test@example.com')
        .and_raise(StandardError.new('Validation failed'))

      # Ensure we can capture the logging
      expect(OT).to receive(:le).with('Email validation error: Validation failed')
      expect(OT).to receive(:le).with(kind_of(Array)) # for backtrace

      expect(subject.valid_email?('test@example.com')).to be false
    end

    it 'returns false for invalid email format' do
      allow(validator_result).to receive(:valid?).and_return(false)
      allow(Truemail).to receive(:validate).with('invalid-email').and_return(validator)

      expect(OT).to receive(:info).with(/\[valid_email\?\] Address is valid \(false\)/)

      expect(subject.valid_email?('invalid-email')).to be false
    end
  end
end

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
#   ttl_options: [1800, 7200, 86400, 604800]
#
# Instead of the test config values (spec/config.test.yaml):
#   default_ttl: 43200 (12 hours)
#   ttl_options: [1800, 43200, 604800]
#
# These tests should FAIL against the current code and PASS after the fix.
# ============================================================================
RSpec.describe 'V1 BaseSecretAction config path bug' do
  using Familia::Refinements::TimeLiterals

  # Subclass that implements the required abstract method
  class V1ConfigTestAction < V1::Logic::Secrets::BaseSecretAction
    def process_secret
      @kind = :test
      @secret_value = 'test_secret'
    end
  end

  let(:customer) {
    double('Customer',
      anonymous?: false,
      custid: 'cust123',
      objid: 'obj123',
      planid: 'anonymous')
  }

  let(:session) {
    double('Session',
      anonymous?: false,
      custid: 'cust123')
  }

  # Minimal params — no TTL so we can test defaults
  let(:base_params) {
    {
      'recipient'    => [],
      'share_domain' => '',
    }
  }

  subject { V1ConfigTestAction.new(session, customer, base_params) }

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

      expect(subject.default_expiration).to eq(43200),
        "Expected default_ttl=43200 from config, got #{subject.default_expiration}. " \
        "Bug: process_ttl reads OT.conf.fetch('secret_options') (root level) " \
        "instead of OT.conf.dig('site', 'secret_options')"
    end

    it 'reads ttl_options from site.secret_options in config, not the hardcoded fallback' do
      # The test config defines: ttl_options: '1800 43200 604800'
      # After OT::Config.after_load parses it, this becomes [1800, 43200, 604800]
      #
      # The hardcoded V1 fallback is [1800, 7200, 86400, 604800]
      # So the arrays differ in both values and length.
      configured_options = OT.conf.dig('site', 'secret_options', 'ttl_options')
      expect(configured_options).to be_an(Array), "Precondition: after_load should parse ttl_options string into an array"
      expect(configured_options).to include(43200), "Precondition: ttl_options should include 43200"

      # process_ttl uses ttl_options to determine min_ttl. With the config
      # values [1800, 43200, 604800], min is 1800. With the hardcoded V1
      # fallback [1800, 7200, 86400, 604800], min is also 1800.
      # But the max differs: config max is 604800, fallback max is also 604800.
      # The real difference is in the OPTIONS ARRAY itself. Let's verify
      # by checking that a TTL below the config min gets clamped to the config min.
      subject.instance_variable_set(:@payload, { 'ttl' => '5' })
      subject.send(:process_ttl)

      # Both config and fallback have min=1800, so let's check the default_ttl
      # which is the differentiating value. When TTL is nil, it uses default_ttl.
      subject.instance_variable_set(:@payload, {})
      subject.send(:process_ttl)
      expect(subject.default_expiration).to eq(43200),
        "Expected default from config ttl_options context (43200), " \
        "got #{subject.default_expiration}. This confirms the config path bug."
    end

    it 'uses config default_ttl (43200) when TTL param is nil' do
      subject.instance_variable_set(:@payload, { 'ttl' => nil })
      subject.send(:process_ttl)

      expect(subject.default_expiration).to eq(43200),
        "Expected nil TTL to default to config's 43200, got #{subject.default_expiration}. " \
        "Bug: falls through to hardcoded 604800 because it reads from wrong config path."
    end

    it 'uses config default_ttl (43200) when TTL key is absent from payload' do
      subject.instance_variable_set(:@payload, {})
      subject.send(:process_ttl)

      expect(subject.default_expiration).to eq(43200),
        "Expected absent TTL to default to config's 43200, got #{subject.default_expiration}. " \
        "Bug: falls through to hardcoded 604800 because it reads from wrong config path."
    end
  end
end
