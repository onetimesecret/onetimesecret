# frozen_string_literal: true

# Run: pnpm run test:rspec spec/unit/onetime/logic/base_spec.rb

require 'spec_helper'
require 'onetime/logic/base'

RSpec.describe Onetime::Logic::Base do
  let(:host_class) do
    Class.new(described_class) do
      def self.name
        'SessionRotationHost'
      end

      attr_writer :auth_logger

      def auth_logger
        @auth_logger
      end
    end
  end

  let(:auth_logger) { double('auth_logger', error: nil) }
  let(:customer) { instance_double(Onetime::Customer, extid: 'ur_rotation') }
  let(:logic) do
    host_class.allocate.tap do |host|
      host.instance_variable_set(:@sess, session)
      host.instance_variable_set(:@cust, customer)
      host.auth_logger = auth_logger
    end
  end
  let(:warning) { 'authentication boundary crossed without rotating the session id' }

  describe '#rotate_session!' do
    context 'when rack.session.options is available' do
      let(:session_options) { {} }
      let(:session) do
        options = session_options
        {}.tap { |value| value.define_singleton_method(:options) { options } }
      end

      it 'requests renewal and reports success' do
        result = logic.send(:rotate_session!, security_warning: warning)

        expect(result).to be(true)
        expect(session_options[:renew]).to be(true)
        expect(auth_logger).not_to have_received(:error)
      end
    end

    context 'when rack.session.options is unavailable' do
      let(:session) { {} }

      it 'logs the security consequence and reports failure' do
        result = logic.send(:rotate_session!, security_warning: warning)

        expect(result).to be(false)
        expect(auth_logger).to have_received(:error).with(
          '[session] rotation unavailable',
          {
            customer_id: 'ur_rotation',
            logic: 'SessionRotationHost',
            security_warning: warning,
          },
        )
      end
    end
  end
end
