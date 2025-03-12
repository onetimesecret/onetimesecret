# tests/unit/ruby/rspec/onetime/logic/secrets/base_secret_action_spec.rb

RSpec.describe Onetime::Logic::Secrets::BaseSecretAction do
  # Create test implementation class
  class TestSecretAction < Onetime::Logic::Secrets::BaseSecretAction
    def process_secret
      @kind = :test
      @secret_value = "test_secret"
    end
  end

  let(:session) { double('Session', event_incr!: nil) }
  let(:customer) { double('Customer',
    anonymous?: false,
    custid: 'cust123',
    planid: 'anonymous'
  ) }

  let(:base_params) {{
    secret: {
      ttl: '7',
      recipient: ['test@example.com'],
      share_domain: 'example.com'
    }
  }}

  subject { TestSecretAction.new(session, customer, base_params) }

  before do
    allow(Onetime::Plan).to receive(:plan).and_return(double('Plan',
      paid?: false,
      options: {size: 1024, ttl: 7.days}
    ))
    allow(Truemail).to receive(:validate).and_return(
      double('Validator', result: double('Result', valid?: true), as_json: '{}')
    )
  end

  describe '#process_ttl' do
    it 'sets default TTL when none provided' do
      subject.instance_variable_set(:@payload, {})
      subject.send(:process_ttl)
      expect(subject.ttl).to eq(12.hours)
    end

    it 'enforces minimum TTL' do
      subject.instance_variable_set(:@payload, {ttl: '30'}) # 30 seconds
      subject.send(:process_ttl)
      expect(subject.ttl).to eq(30.minutes)
    end

    it 'enforces minimum TTL' do
      subject.instance_variable_set(:@payload, {'ttl' => '30'}) # 30 seconds
      subject.send(:process_ttl)
      expect(subject.ttl).to eq(30.minutes) # See config.test.yaml
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
