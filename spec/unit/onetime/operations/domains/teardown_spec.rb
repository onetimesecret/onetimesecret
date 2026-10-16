# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/domains/teardown'
require 'onetime/operations/provision_sender_domain'

RSpec.describe Onetime::Operations::Domains::Teardown do
  describe 'teardown contract' do
    let(:mailer_config) { double('MailerConfig') }
    let(:domain) do
      instance_double(Onetime::CustomDomain,
        identifier: 'domain123', display_domain: 'example.com',
        mailer_config: mailer_config, destroy!: true)
    end
    let(:strategy) { double('Strategy', delete_vhost: { message: 'deleted' }) }
    let(:sender_op) { double('DeleteSenderDomain', call: nil) }
    let(:lock) do
      double('Familia::Lock', acquire: 'lock-token', release: true,
        dbkey: 'sender-identity-lock', dbclient: double('Redis', eval: 1))
    end

    before do
      allow(Onetime::CustomDomain::MailerConfig).to receive(:sender_identity_lock)
        .with('domain123').and_return(lock)
      allow(Onetime::DomainValidation::Strategy).to receive(:for_config).and_return(strategy)
      allow(Onetime::Operations::DeleteSenderDomain).to receive(:new).and_return(sender_op)
    end

    it 'holds the lease across vhost, sender, and destroy, checking ownership between steps' do
      calls = []
      allow(lock).to receive(:acquire) { calls << :acquire; 'lock-token' }
      allow(lock.dbclient).to receive(:eval) { calls << :check; 1 }
      allow(strategy).to receive(:delete_vhost) { calls << :vhost; { message: 'deleted' } }
      allow(sender_op).to receive(:call) { calls << :sender }
      allow(domain).to receive(:destroy!) { calls << :destroy }
      allow(lock).to receive(:release) { calls << :release }

      result = described_class.new(domain: domain).call

      expect(result).to eq(described_class::Result.new(removal_committed: true, lease_error: nil))
      expect(Onetime::Operations::DeleteSenderDomain).to have_received(:new).with(mailer_config: mailer_config)
      expect(strategy).to have_received(:delete_vhost).with(domain)
      expect(lock).to have_received(:acquire).with(ttl: 60)
      expect(lock).to have_received(:release).with('lock-token')
      expect(calls).to eq([:acquire, :check, :vhost, :check, :sender, :check, :destroy, :check, :release])
    end

    it 'leaves the provider vhost in place with keep_vhost and still tears down the rest' do
      result = described_class.new(domain: domain, keep_vhost: true).call

      expect(result).to eq(described_class::Result.new(removal_committed: true, lease_error: nil))
      expect(strategy).not_to have_received(:delete_vhost)
      expect(sender_op).to have_received(:call)
      expect(domain).to have_received(:destroy!)
    end

    context 'without a mailer config' do
      let(:mailer_config) { nil }

      it 'passes nil to sender teardown and still commits destruction' do
        result = described_class.new(domain: domain).call

        expect(Onetime::Operations::DeleteSenderDomain).to have_received(:new).with(mailer_config: nil)
        expect(sender_op).to have_received(:call).once
        expect(domain).to have_received(:destroy!).once
        expect(result).to eq(described_class::Result.new(removal_committed: true, lease_error: nil))
      end
    end

    it 'reports local commitment even when sender cleanup returns a failure' do
      allow(sender_op).to receive(:call).and_return(
        Onetime::Operations::DeleteSenderDomain::Result.new(success: false, message: nil, error: 'provider unavailable')
      )

      result = described_class.new(domain: domain).call

      expect(domain).to have_received(:destroy!).once
      expect(result).to eq(described_class::Result.new(removal_committed: true, lease_error: nil))
    end

    it 'raises Busy naming the domain before any teardown on contention' do
      allow(lock).to receive(:acquire).and_return(false)

      expect { described_class.new(domain: domain).call }
        .to raise_error(described_class::Busy) { |error| expect(error.message).to include('example.com') }

      expect(strategy).not_to have_received(:delete_vhost)
      expect(Onetime::Operations::DeleteSenderDomain).not_to have_received(:new)
      expect(domain).not_to have_received(:destroy!)
      expect(lock).not_to have_received(:release)
    end

    it 'stops before vhost teardown if the first ownership check fails' do
      allow(lock.dbclient).to receive(:eval).and_return(0)

      expect { described_class.new(domain: domain).call }
        .to raise_error(Onetime::Operations::SenderIdentityLease::Lost)

      expect(strategy).not_to have_received(:delete_vhost)
      expect(sender_op).not_to have_received(:call)
      expect(domain).not_to have_received(:destroy!)
      expect(lock).to have_received(:release).with('lock-token')
    end

    [:vhost, :sender].each do |phase|
      [0, IOError.new('renewal unavailable')].each do |failure|
        it "stops after #{phase} on #{failure.inspect}, retaining the record" do
          lose_lease = proc do
            if failure.is_a?(Exception)
              allow(lock.dbclient).to receive(:eval).and_raise(failure)
            else
              allow(lock.dbclient).to receive(:eval).and_return(failure)
            end
            { message: 'done' }
          end
          if phase == :vhost
            allow(strategy).to receive(:delete_vhost, &lose_lease)
          else
            allow(sender_op).to receive(:call, &lose_lease)
          end

          expect { described_class.new(domain: domain).call }
            .to raise_error(Onetime::Operations::SenderIdentityLease::Lost)

          expect(sender_op).not_to have_received(:call) if phase == :vhost
          expect(domain).not_to have_received(:destroy!)
          expect(lock).to have_received(:release).with('lock-token')
        end
      end
    end

    [HTTParty::ResponseError, Timeout::Error, Errno::ECONNREFUSED].each do |error_class|
      it "continues sender teardown and destruction after vhost #{error_class}" do
        allow(strategy).to receive(:delete_vhost).and_raise(error_class, 'provider unavailable')

        result = described_class.new(domain: domain).call

        expect(result.removal_committed).to be true
        expect(result.lease_error).to be_nil
        expect(sender_op).to have_received(:call).once
        expect(domain).to have_received(:destroy!).once
      end
    end

    [:vhost, :sender, :destroy].each do |phase|
      [RuntimeError, Onetime::Operations::SenderIdentityLease::Lost].each do |error_class|
        it "propagates #{error_class} unchanged from #{phase}, without claiming commitment" do
          error = error_class.new('operation failed')
          target, method = case phase
                           when :vhost then [strategy, :delete_vhost]
                           when :sender then [sender_op, :call]
                           else [domain, :destroy!]
                           end
          allow(target).to receive(method).and_raise(error)

          expect { described_class.new(domain: domain).call }.to raise_error { |ex| expect(ex).to equal(error) }

          expect(sender_op).not_to have_received(:call) if phase == :vhost
          expect(domain).not_to have_received(:destroy!) unless phase == :destroy
          expect(lock).to have_received(:release).with('lock-token')
        end
      end
    end

    it 'returns the final lease loss only after destroy has returned' do
      error = Onetime::Operations::SenderIdentityLease::Lost.new('lock lost after destroy')
      lease = instance_double(Onetime::Operations::SenderIdentityLease, acquire: true, check!: nil)
      allow(Onetime::Operations::SenderIdentityLease).to receive(:new).with(lock).and_return(lease)
      allow(lease).to receive(:protect) do |&block|
        block.call(lease)
        raise error
      end

      result = described_class.new(domain: domain).call

      expect(domain).to have_received(:destroy!).once
      expect(result.removal_committed).to be true
      expect(result.lease_error).to equal(error)
    end

    it 'does not capture unexpected errors after destroy has returned' do
      error = IOError.new('unexpected finalization error')
      lease = instance_double(Onetime::Operations::SenderIdentityLease, acquire: true, check!: nil)
      allow(Onetime::Operations::SenderIdentityLease).to receive(:new).with(lock).and_return(lease)
      allow(lease).to receive(:protect) do |&block|
        block.call(lease)
        raise error
      end

      expect { described_class.new(domain: domain).call }.to raise_error { |ex| expect(ex).to equal(error) }
      expect(domain).to have_received(:destroy!).once
    end
  end

  describe 'real datastore', :datastore do
    before do
      @records = []
    end

    after do
      @records.each { |record| record.destroy! if record.exists? }
    end

    def create_domain(fqdn, org_id)
      Onetime::CustomDomain.create!(fqdn, org_id).tap { |record| @records << record }
    end

    def unique_fqdn(prefix)
      "#{prefix}-#{SecureRandom.hex(4)}.example.com"
    end

    context 'with the sender identity lock' do
      let(:model) { Onetime::CustomDomain::MailerConfig }
      let(:domain) { create_domain(unique_fqdn('lock'), "org-#{SecureRandom.hex(3)}") }
      let(:lock) { model.sender_identity_lock(domain.identifier) }

      before do
        model.create!(
          domain_id: domain.identifier,
          provider: 'ses',
          from_address: 'remove-lock@example.com',
        )
      end

      def stub_teardown
        allow_any_instance_of(Onetime::Operations::DeleteSenderDomain).to receive(:call) do
          yield
          Onetime::Operations::DeleteSenderDomain::Result.new(success: true, message: 'stubbed', error: nil)
        end
      end

      def provision(config, strategy)
        Onetime::Operations::ProvisionSenderDomain.new(mailer_config: config, strategy: strategy).call
      end

      it 'refuses and keeps the domain and its sender config while another holder has the lock' do
        token = lock.acquire(ttl: 60)

        expect do
          described_class.new(domain: domain).call
        end.to raise_error(described_class::Busy)

        expect(domain.exists?).to be true
        expect(model.exists_for_domain?(domain.identifier)).to be true
      ensure
        lock.release(token)
      end

      it 'holds the lock from the provider teardown through destroy!' do
        seen = {}
        stub_teardown { seen[:teardown] = [lock.locked?, model.exists_for_domain?(domain.identifier)] }
        allow(domain).to receive(:destroy!).and_wrap_original do |original|
          seen[:destroy] = lock.locked?
          original.call
        end

        result = described_class.new(domain: domain).call

        expect(result.removal_committed).to be true
        expect(seen).to eq(teardown: [true, true], destroy: true)
        expect(lock.locked?).to be false
        expect(model.exists_for_domain?(domain.identifier)).to be false
      end

      [:vhost, :sender, :destroy].each do |phase|
        it "renews throughout slow #{phase} work beyond the initial lease" do
          stub_const('Onetime::Operations::SenderIdentityLease::TTL', 1)
          stub_const('Onetime::Operations::SenderIdentityLease::RENEW_INTERVAL', 0.05)
          stale = model.find_by_domain_id(domain.identifier)
          sender_strategy = spy('sender strategy')
          hold = proc do
            token = lock.value
            sleep 1.2
            expect(lock.held_by?(token)).to be true
            expect(lock.acquire(ttl: 1)).to be false
            expect(provision(stale, sender_strategy).error).to include('already in progress')
          end
          stub_teardown { hold.call if phase == :sender }
          if phase == :vhost
            vhost_strategy = double('vhost strategy')
            allow(vhost_strategy).to receive(:delete_vhost) { hold.call; { message: 'done' } }
            allow(Onetime::DomainValidation::Strategy).to receive(:for_config).and_return(vhost_strategy)
          elsif phase == :destroy
            allow(domain).to receive(:destroy!).and_wrap_original { |original| hold.call; original.call }
          end

          result = described_class.new(domain: domain).call

          expect(result.removal_committed).to be true
          expect(domain.exists?).to be false
          expect(lock.locked?).to be false
          expect(sender_strategy).not_to have_received(:provision_dns_records)
        end
      end

      it 'stops before destroy if the watchdog fails during a provider call, even after Redis recovers' do
        stub_const('Onetime::Operations::SenderIdentityLease::RENEW_INTERVAL', 0.01)
        client = lock.dbclient
        allow(lock).to receive(:dbclient).and_return(client)
        allow(model).to receive(:sender_identity_lock).with(domain.identifier).and_return(lock)
        allow(client).to receive(:eval).and_call_original
        attempted = Queue.new
        stub_teardown do
          allow(client).to receive(:eval)
            .with(Onetime::Operations::SenderIdentityLease::RENEW_SCRIPT, [lock.dbkey], anything) do
              attempted << true
              raise IOError, 'renewal unavailable'
            end
          Timeout.timeout(3) { attempted.pop }
          allow(client).to receive(:eval)
            .with(Onetime::Operations::SenderIdentityLease::RENEW_SCRIPT, [lock.dbkey], anything).and_return(1)
        end

        expect do
          described_class.new(domain: domain).call
        end.to raise_error(Onetime::Operations::SenderIdentityLease::Lost, /renewal failed/)

        expect(domain.exists?).to be true
        expect(model.exists_for_domain?(domain.identifier)).to be true
        expect(lock.locked?).to be false
      end

      it 'preserves the successor token when ownership changes during teardown' do
        successor = nil
        stub_teardown do
          lock.force_unlock!
          successor = lock.acquire(ttl: 60)
        end

        expect { described_class.new(domain: domain).call }
          .to raise_error(Onetime::Operations::SenderIdentityLease::Lost, /lock lost/)

        expect(domain.exists?).to be true
        expect(model.exists_for_domain?(domain.identifier)).to be true
        expect(lock.held_by?(successor)).to be true
      ensure
        lock.release(successor) if successor
      end

      it 'returns committed lease loss after real destruction without releasing a successor token' do
        successor = nil
        stub_teardown {}
        allow(domain).to receive(:destroy!).and_wrap_original do |original|
          value = original.call
          lock.force_unlock!
          successor = lock.acquire(ttl: 60)
          value
        end

        result = described_class.new(domain: domain).call

        expect(result.removal_committed).to be true
        expect(result.lease_error).to be_a(Onetime::Operations::SenderIdentityLease::Lost)
        expect(domain.exists?).to be false
        expect(model.exists_for_domain?(domain.identifier)).to be false
        expect(lock.held_by?(successor)).to be true
      ensure
        lock.release(successor) if successor
      end

      it 'does not provision during the removal, nor afterwards from a config loaded before it' do
        stale       = model.find_by_domain_id(domain.identifier)
        strategy    = spy('sender strategy')
        provisioned = nil
        stub_teardown { provisioned = provision(stale, strategy) }

        described_class.new(domain: domain).call
        after_removal = provision(stale, strategy)

        expect(provisioned.error).to include('already in progress')
        expect(after_removal.error).to include('was deleted')
        expect(strategy).not_to have_received(:provision_dns_records)
      end
    end
  end
end
