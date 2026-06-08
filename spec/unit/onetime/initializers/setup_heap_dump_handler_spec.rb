# spec/unit/onetime/initializers/setup_heap_dump_handler_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'objspace' # define ObjectSpace.dump_all so verifying doubles can stub it
require 'onetime/initializers/setup_heap_dump_handler'

RSpec.describe Onetime::Initializers::SetupHeapDumpHandler do
  let(:instance) { described_class.new }
  let(:context) { double('context') }
  let(:logger) { instance_double('SemanticLogger::Logger', info: nil, error: nil, debug: nil) }

  before do
    allow(Onetime).to receive(:boot_logger).and_return(logger)
  end

  describe 'metadata' do
    it 'provides the :heap_dump capability' do
      expect(described_class.provides).to eq([:heap_dump])
    end

    it 'is optional so a failed handler install never blocks boot' do
      expect(described_class.optional).to be true
    end

    it 'is NOT fork-sensitive so forked workers inherit the handler' do
      # Marking it :fork_sensitive would have cleanup_before_fork tear it down
      # before Puma/Sneakers workers are spawned, losing the handler.
      expect(described_class.phase).to eq(:preload)
    end

    it 'defaults the dump directory to the disk-backed /var/tmp' do
      # /tmp is tmpfs on Debian 13; a large dump there consumes RAM and is lost
      # on restart, so the default must be disk-backed.
      expect(described_class::DUMP_DIR).to eq('/var/tmp')
    end
  end

  describe '#should_skip?' do
    around do |example|
      original = ENV.fetch('HEAP_DUMP_ENABLED', nil)
      example.run
    ensure
      if original.nil?
        ENV.delete('HEAP_DUMP_ENABLED')
      else
        ENV['HEAP_DUMP_ENABLED'] = original
      end
    end

    it 'skips (handler not installed) when HEAP_DUMP_ENABLED is unset' do
      ENV.delete('HEAP_DUMP_ENABLED')
      expect(instance.should_skip?).to be true
    end

    it 'skips when HEAP_DUMP_ENABLED is a falsey value' do
      ENV['HEAP_DUMP_ENABLED'] = 'false'
      expect(instance.should_skip?).to be true
    end

    it 'runs when HEAP_DUMP_ENABLED is truthy' do
      ENV['HEAP_DUMP_ENABLED'] = 'true'
      expect(instance.should_skip?).to be false
    end
  end

  describe '#execute' do
    # Every example here stubs Signal.trap, so no real USR2 handler is ever
    # installed in the test process — nothing to restore afterwards.

    it 'installs a USR2 signal handler' do
      expect(Signal).to receive(:trap).with('USR2')
      instance.execute(context)
    end

    it 'logs that the handler was installed' do
      allow(Signal).to receive(:trap)
      instance.execute(context)
      expect(logger).to have_received(:debug).with(/heap dump handler installed/)
    end

    context 'when the trap fires' do
      let(:fake_io) { StringIO.new }
      # Mutable container holding the USR2 handler block captured from the
      # stubbed Signal.trap (avoids an example-scoped instance variable).
      let(:captured) { {} }

      before do
        # Capture the trap block instead of installing it, and run any spawned
        # thread synchronously for deterministic assertions.
        allow(Signal).to receive(:trap).with('USR2') { |&block| captured[:handler] = block }
        allow(Thread).to receive(:new).and_yield
        allow(File).to receive(:open).and_yield(fake_io)
        allow(ObjectSpace).to receive(:dump_all)
      end

      it 'writes a heap dump and logs the path' do
        instance.execute(context)
        captured[:handler].call

        expect(ObjectSpace).to have_received(:dump_all).with(output: fake_io)
        expect(logger).to have_received(:info).with(%r{\[heap\] Dump written to .*heap-#{Process.pid}-\d+\.json})
      end

      it 'logs an error instead of raising when the dump fails' do
        allow(ObjectSpace).to receive(:dump_all).and_raise(Errno::EACCES, 'no write')

        instance.execute(context)
        expect { captured[:handler].call }.not_to raise_error
        expect(logger).to have_received(:error).with(/\[heap\] Dump failed: Errno::EACCES/)
      end

      it 'creates the dump owner-only and refuses to follow an existing file' do
        # The dump contains plaintext secrets; it must be 0600 and must not
        # clobber/follow a pre-existing path (symlink defense in a shared dir).
        expect(File).to receive(:open)
          .with(anything, File::WRONLY | File::CREAT | File::EXCL, 0o600)
          .and_yield(fake_io)

        instance.execute(context)
        captured[:handler].call
        expect(ObjectSpace).to have_received(:dump_all).with(output: fake_io)
      end
    end
  end
end
