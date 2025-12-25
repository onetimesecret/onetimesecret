# spec/lib/onetime/initializers/setup_loggers_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/SpecFilePathFormat
# File name matches implementation file setup_loggers.rb
RSpec.describe Onetime::Initializers::SetupLoggers do
  # These tests use mocks to avoid requiring full SemanticLogger configuration

  let(:instance) { described_class.new }

  describe '#cleanup' do
    context 'when SemanticLogger is defined' do
      before do
        stub_const('SemanticLogger', Class.new) unless defined?(SemanticLogger)
        allow(SemanticLogger).to receive(:flush)
      end

      it 'calls SemanticLogger.flush' do
        instance.cleanup
        expect(SemanticLogger).to have_received(:flush)
      end

      it 'does not raise on success' do
        expect { instance.cleanup }.not_to raise_error
      end

      context 'when flush raises an error' do
        before do
          allow(SemanticLogger).to receive(:flush)
            .and_raise(StandardError.new('Flush failed'))
        end

        it 'does not raise error' do
          expect { instance.cleanup }.not_to raise_error
        end

        it 'logs warning to stderr' do
          expect { instance.cleanup }.to output(/SetupLoggers.*Error during cleanup.*Flush failed/).to_stderr
        end

        it 'is idempotent' do
          expect { instance.cleanup }.not_to raise_error
          expect { instance.cleanup }.not_to raise_error
        end
      end
    end

    context 'when SemanticLogger is not defined' do
      before do
        hide_const('SemanticLogger') if defined?(SemanticLogger)
      end

      it 'does not raise error' do
        expect { instance.cleanup }.not_to raise_error
      end

      it 'handles gracefully' do
        # Should complete without attempting to call undefined constant
        instance.cleanup
        # Test passes if no NameError is raised
      end
    end
  end

  describe '#reconnect' do
    context 'when SemanticLogger is defined' do
      before do
        stub_const('SemanticLogger', Class.new) unless defined?(SemanticLogger)
        allow(SemanticLogger).to receive(:reopen)
      end

      it 'calls SemanticLogger.reopen' do
        instance.reconnect
        expect(SemanticLogger).to have_received(:reopen)
      end

      it 'does not raise on success' do
        expect { instance.reconnect }.not_to raise_error
      end

      context 'when reopen raises an error' do
        before do
          allow(SemanticLogger).to receive(:reopen)
            .and_raise(StandardError.new('Reopen failed'))
        end

        it 'does not raise error' do
          expect { instance.reconnect }.not_to raise_error
        end

        it 'logs warning to stderr' do
          expect { instance.reconnect }.to output(/SetupLoggers.*Error during reconnect.*Reopen failed/).to_stderr
        end

        it 'is idempotent' do
          expect { instance.reconnect }.not_to raise_error
          expect { instance.reconnect }.not_to raise_error
        end
      end
    end

    context 'when SemanticLogger is not defined' do
      before do
        hide_const('SemanticLogger') if defined?(SemanticLogger)
      end

      it 'does not raise error' do
        expect { instance.reconnect }.not_to raise_error
      end

      it 'handles gracefully' do
        # Should complete without attempting to call undefined constant
        instance.reconnect
        # Test passes if no NameError is raised
      end
    end
  end
end
