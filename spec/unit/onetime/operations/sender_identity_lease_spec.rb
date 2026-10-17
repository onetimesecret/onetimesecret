# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/sender_identity_lease'

RSpec.describe Onetime::Operations::SenderIdentityLease do
  let(:lock) { double('Familia::Lock', acquire: 'owner', release: true, dbkey: 'sender-identity', dbclient: client) }
  let(:client) { double('Redis', eval: 1) }
  let(:lease) { described_class.new(lock) }

  it 'does not release or start a renewer when acquisition is refused' do
    allow(lock).to receive(:acquire).and_return(false)

    expect(lease.acquire).to be false
    expect(lock).not_to have_received(:release)
    expect(client).not_to have_received(:eval)
  end

  it 'checks the token and extends the TTL in one Lua operation' do
    lease.acquire
    expect(lease.protect { :done }).to eq(:done)

    expect(client).to have_received(:eval).with(described_class::RENEW_SCRIPT, ['sender-identity'], ['owner', 60]).twice
    expect(lock).to have_received(:release).with('owner')
    expect(lease.instance_variable_get(:@renewer)).not_to be_alive
  end

  it 'treats an elapsed local deadline as lost even if Redis still holds the token' do
    now = 0.0
    allow(lease).to receive(:monotonic_now) { now }
    lease.acquire

    expect { lease.protect { now = 61.0 } }.to raise_error(described_class::Lost, /deadline elapsed/)
    expect(client).to have_received(:eval).once
    expect(lock).to have_received(:release).with('owner')
  end

  it 'rejects a renewal whose response arrives after the previous deadline' do
    now = 0.0
    allow(lease).to receive(:monotonic_now) { now }
    lease.acquire
    allow(client).to receive(:eval) { now = 61.0; 1 }

    expect { lease.protect { raise 'must not start provider work' } }
      .to raise_error(described_class::Lost, /response arrived after/)
    expect(lock).to have_received(:release).with('owner')
  end

  it 'joins the renewer and releases the lock without replacing a block exception' do
    lease.acquire

    expect { lease.protect { raise ArgumentError, 'provider failed' } }.to raise_error(ArgumentError, 'provider failed')
    expect(lease.instance_variable_get(:@renewer)).not_to be_alive
    expect(lock).to have_received(:release).with('owner')
  end

  def return_from_protected_block(lease)
    lease.protect { return :early }
  end

  it 'joins the renewer and releases on a nonlocal return' do
    lease.acquire

    expect(return_from_protected_block(lease)).to eq(:early)
    expect(lease.instance_variable_get(:@renewer)).not_to be_alive
    expect(lock).to have_received(:release).with('owner')
  end

  it 'does not mask the original failure if release also fails' do
    lease.acquire
    allow(lock).to receive(:release).and_raise(IOError, 'cleanup unavailable')
    expect(OT).to receive(:le).with(/Lock release failed/)

    expect { lease.protect { raise ArgumentError, 'provider failed' } }.to raise_error(ArgumentError, 'provider failed')
  end

  context 'with real Valkey', :datastore do
    let(:lock) { Onetime::CustomDomain::MailerConfig.sender_identity_lock("lease-spec-#{SecureRandom.hex(8)}") }
    let(:client) { lock.dbclient }

    before do
      # Shorten the real lease, not wall time: Redis expiry and the watchdog
      # both run normally, including while the calling thread is blocked.
      stub_const("#{described_class}::TTL", 1)
      stub_const("#{described_class}::RENEW_INTERVAL", 0.05)
    end

    after { lock.force_unlock! }

    it 'keeps the same token beyond the initial TTL and stops renewing before release' do
      token = lease.acquire
      lease.protect do
        sleep 1.2
        expect(lock.held_by?(token)).to be true
        expect(lock.acquire(ttl: 1)).to be false
      end

      expect(lock.locked?).to be false
      expect(lease.instance_variable_get(:@renewer)).not_to be_alive
    end

    it 'never extends or releases a successor owner after losing the token' do
      token = lease.acquire
      successor = nil

      expect do
        lease.protect do
          lock.release(token)
          successor = lock.acquire(ttl: 30)
        end
      end.to raise_error(described_class::Lost, /token no longer belongs/)

      expect(lock.held_by?(successor)).to be true
      expect(client.ttl(lock.dbkey)).to be_between(25, 30)
    end

    [0, IOError.new('renewal unavailable')].each do |failure|
      it "remembers watchdog failure #{failure.inspect} even after Redis recovers" do
        lease.acquire
        attempted = Queue.new
        allow(lock).to receive(:dbclient).and_return(client)
        allow(client).to receive(:eval).and_call_original

        expect do
          lease.protect do
            allow(client).to receive(:eval).with(described_class::RENEW_SCRIPT, [lock.dbkey], anything) do
              attempted << true
              raise failure if failure.is_a?(Exception)

              failure
            end
            Timeout.timeout(3) { attempted.pop }
            # The check waits for the watchdog's mutex, so the failed result
            # is recorded even if Redis recovers before this caller resumes.
            allow(client).to receive(:eval).with(described_class::RENEW_SCRIPT, [lock.dbkey], anything).and_return(1)
            lease.check!
          end
        end.to raise_error(described_class::Lost, /lock lost/)

        expect(lock.locked?).to be false
        expect(lease.instance_variable_get(:@renewer)).not_to be_alive
      end
    end
  end
end
