# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../apps/api/incoming/application'

RSpec.describe 'Incoming provenance at first receipt persistence', type: :integration do
  before(:all) { Onetime.boot! :test }

  def incoming_logic(domain: nil, extra_payload: {})
    strategy = double('IncomingStrategy', user: nil, session: {}, auth_method: 'noauth',
      metadata: { domain_strategy: domain ? 'custom' : 'canonical', display_domain: domain })
    logic = Incoming::Logic::CreateIncomingSecret.new(strategy,
      { 'secret' => { 'secret' => 'incoming provenance fixture', 'recipient' => 'a' * 64,
        'memo' => 'Incoming <b>memo</b>' }.merge(extra_payload) })
    resolver = instance_double(Onetime::Incoming::RecipientResolver,
      require_domain_entitlement!: true, enabled?: true,
      config_data: { default_ttl: 3600, memo_max_length: 50 },
      lookup: 'configured-recipient@example.com',
      public_recipients: [{ 'digest' => 'a' * 64, 'display_name' => 'Configured recipient' }])
    allow(logic).to receive(:resolver).and_return(resolver)
    allow(logic).to receive(:enforce_incoming_rate_limit!).and_return(true)
    allow(Onetime::CustomDomain).to receive(:resolve_domain_id).with(domain)
      .and_return(domain ? 'configured-domain-id' : nil)
    logic.raise_concerns
    logic
  end

  # Snapshot the stored receipt right after each creation commit, before any
  # post-commit follow-up can write to it.
  def observe_receipt_commits
    snapshots = []
    allow(Familia).to receive(:atomic_write).and_wrap_original do |original, *instances, **kwargs, &block|
      result = original.call(*instances, **kwargs, &block)
      receipt = instances.find { |instance| instance.is_a?(Onetime::Receipt) }
      snapshots << Onetime::Receipt.load(receipt.identifier)
      result
    end
    snapshots
  end

  def expect_incoming_metadata(receipt, domain: nil)
    expect(receipt.source).to eq('incoming')
    expect(receipt.memo).to eq('Incoming memo')
    expect(receipt.recipients).to eq('configured-recipient@example.com')
    expect(receipt.recipient_name).to eq('Configured recipient')
    expect(receipt.share_domain).to eq(domain)
    expect(receipt.domain_id).to eq(domain ? 'configured-domain-id' : nil)
    expect(receipt.safe_dump).to include(source: 'incoming', secret_identifier: nil,
      owner_id: nil, custid: nil)
    expect(receipt.safe_dump[:recipients]).not_to include('configured-recipient@example.com')
  end

  [nil, 'incoming.example.com'].each do |domain|
    describe(domain || 'canonical domain') do
      it 'persists all selected metadata and withholds the share key in the creation commit' do
        logic = incoming_logic(domain: domain)
        snapshots = observe_receipt_commits

        logic.send(:create_and_encrypt_secret)

        expect(snapshots.length).to eq(1)
        expect_incoming_metadata(snapshots.first, domain: domain)
        expect_incoming_metadata(Onetime::Receipt.load(logic.receipt.identifier), domain: domain)
        expect(logic.secret.share_domain).to eq(domain)
      end

      it 'keeps the committed Incoming pair when a post-commit spawn_pair follow-up raises' do
        logic = incoming_logic(domain: domain)
        snapshots = observe_receipt_commits
        allow_any_instance_of(Onetime::Receipt).to receive(:register_for_expiration_notifications)
          .and_raise(IOError, 'injected post-commit registration failure')

        expect { logic.send(:create_and_encrypt_secret) }.not_to raise_error

        expect(snapshots.length).to eq(1)
        stored = Onetime::Receipt.load(snapshots.first.identifier)
        expect_incoming_metadata(stored, domain: domain)
        expect(stored.load_secret).not_to be_nil
      end
    end
  end

  it 'ignores client provenance, recipient metadata and domain identifiers' do
    logic = incoming_logic(domain: 'incoming.example.com', extra_payload: {
      'source' => 'standard', 'recipients' => 'attacker@example.com',
      'recipient_name' => 'Unconfigured recipient', 'domain_id' => 'client-domain-id',
      'share_domain' => 'attacker.example.com', 'owner_id' => 'client-owner',
    })
    snapshots = observe_receipt_commits

    logic.send(:create_and_encrypt_secret)

    expect(snapshots.length).to eq(1)
    expect_incoming_metadata(snapshots.first, domain: 'incoming.example.com')
    expect(snapshots.first.owner_id).to eq('anon')
  end

  it 'does not save the receipt again after the Incoming creation commit' do
    logic = incoming_logic
    # Mock expectation errors are not StandardErrors, so a follow-up's rescue
    # cannot swallow a violation.
    expect_any_instance_of(Onetime::Receipt).not_to receive(:save)
    expect_any_instance_of(Onetime::Receipt).not_to receive(:save_fields)

    expect { logic.process }.not_to raise_error
    expect_incoming_metadata(Onetime::Receipt.load(logic.receipt.identifier))
  end

  it 'reports success with selected metadata when a post-commit stats follow-up raises' do
    logic = incoming_logic
    allow(Onetime::Customer).to receive(:secrets_created).and_raise(IOError, 'injected stats failure')

    expect(logic.process).to include(success: true)

    expect_incoming_metadata(Onetime::Receipt.load(logic.receipt.identifier))
    expect(Onetime::Secret.load(logic.secret.identifier)).not_to be_nil
  end

  it 'preserves ordinary spawn_pair defaults and its existing share-key projection' do
    snapshots = observe_receipt_commits
    receipt, secret = Onetime::Receipt.spawn_pair(nil, 3600, 'ordinary pair fixture',
      domain: 'ordinary.example.com', kind: 'conceal')
    stored = Onetime::Receipt.load(receipt.identifier)

    expect(snapshots.length).to eq(1)
    expect(stored.source).to eq('standard')
    expect(stored.memo).to be_nil
    expect(stored.recipients).to be_nil
    expect(stored.recipient_name).to be_nil
    expect(stored.domain_id).to be_nil
    expect(stored.share_domain).to eq('ordinary.example.com')
    expect(stored.kind).to eq('conceal')
    expect(stored.safe_dump[:secret_identifier]).to eq(secret.identifier)
    expect(secret.decrypted_secret_value).to eq('ordinary pair fixture')
    expect(stored.dbclient.ttl(stored.dbkey)).to be_between(1, 7200)
  end
end
