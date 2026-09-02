# spec/unit/onetime/initializers/setup_loggers_spec.rb
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

  # #4334 — the OPTIONAL second destination for the operator audit sink. Every
  # ColonelAuditEvent already rides the console appender (stdout); this ships a
  # copy to syslog for operators who want the audit stream separated from
  # application logs. Default OFF, and never allowed to break boot.
  describe '#configure_audit_syslog_appender' do
    before { allow(SemanticLogger).to receive(:add_appender) }

    def configure(settings)
      instance.send(:configure_audit_syslog_appender, { 'audit' => { 'syslog' => settings } })
    end

    it 'does nothing when the config section is absent' do
      instance.send(:configure_audit_syslog_appender, {})

      expect(SemanticLogger).not_to have_received(:add_appender)
    end

    it 'is DEFAULT OFF: an unset or false enabled flag adds no appender' do
      configure({})
      configure('enabled' => false)
      configure('enabled' => 'no')

      expect(SemanticLogger).not_to have_received(:add_appender)
    end

    it 'adds a syslog appender FILTERED to the audit category when enabled' do
      configure('enabled' => true, 'url' => 'tcp://loghost:514', 'level' => 'info', 'facility' => 'local3')

      expect(SemanticLogger).to have_received(:add_appender).once.with(
        hash_including(
          appender: :syslog,
          url: 'tcp://loghost:514',
          level: :info,
          facility: ::Syslog::LOG_LOCAL3,
        ),
      )
    end

    # A loose filter would quietly start copying unrelated categories into the
    # operator's audit destination.
    it 'filters on the audit category name EXACTLY' do
      configure('enabled' => true)

      expect(SemanticLogger).to have_received(:add_appender)
        .with(hash_including(filter: /\AColonelAudit\z/))
    end

    # The appender's own level_map DEFAULT autoloads a formatter that requires
    # the third-party syslog_protocol gem — even for local syslog. Supplying the
    # map explicitly is what keeps the local path dependency-free.
    it 'supplies the level map explicitly so the local path needs no extra gem' do
      configure('enabled' => true)

      expect(SemanticLogger).to have_received(:add_appender).with(
        hash_including(level_map: hash_including(info: ::Syslog::LOG_NOTICE, error: ::Syslog::LOG_ERR)),
      )
    end

    it 'defaults the URL to the local syslog daemon (no third-party gem)' do
      configure('enabled' => true, 'url' => '')

      expect(SemanticLogger).to have_received(:add_appender)
        .with(hash_including(url: 'syslog://localhost'))
    end

    it 'falls back to LOG_USER for an unrecognised facility rather than raising' do
      configure('enabled' => true, 'facility' => 'not-a-facility')

      expect(SemanticLogger).to have_received(:add_appender)
        .with(hash_including(facility: ::Syslog::LOG_USER))
    end

    it 'is idempotent: a second pass does not stack a duplicate appender' do
      # allocate, not instance_double: the guard matches on the CLASS NAME (the
      # constant only exists once add_appender has loaded the appender file), and
      # a verifying double's class name is RSpec's, not the appender's.
      allow(SemanticLogger).to receive(:appenders)
        .and_return([SemanticLogger::Appender::Syslog.allocate])

      configure('enabled' => true)

      expect(SemanticLogger).not_to have_received(:add_appender)
    end

    # An optional log destination must never cost the process its boot: the
    # audit stream still reaches stdout, so only the second copy is lost.
    it 'warns instead of raising when the appender cannot be built' do
      # The real shape of this: a tcp:// or udp:// URL, which ships to a REMOTE
      # syslog server and needs the syslog_protocol gem this repo does not
      # bundle.
      allow(SemanticLogger).to receive(:add_appender).and_raise(LoadError, 'syslog_protocol missing')

      expect { configure('enabled' => true, 'url' => 'udp://loghost:514') }
        .to output(/SetupLoggers.*audit syslog appender not enabled.*syslog_protocol missing/).to_stderr
    end
  end
end
