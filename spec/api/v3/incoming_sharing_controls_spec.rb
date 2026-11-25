# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../apps/api/incoming/application'

RSpec.describe 'Incoming Secrets creation controls', type: :integration do
  before(:all) { Onetime.boot! :test }

  let(:run_id) { SecureRandom.hex(6) }
  let(:owner) { Onetime::Customer.create!(email: "#{run_id}@example.com") }
  let(:organization) { Onetime::Organization.create!("Incoming #{run_id}", owner, owner.email) }
  let(:domain) { Onetime::CustomDomain.create!("incoming-#{run_id}.example.com", organization.objid) }
  let(:recipient) { 'help@example.net' }
  let(:phrase) { ' Sender passphrase! 23 ' }
  let(:strategy) do
    double('IncomingStrategy', user: nil, session: {}, auth_method: 'noauth', metadata: {
      domain_strategy: :custom, display_domain: domain.display_domain, custom_domain_id: domain.identifier,
      custom_domain_lookup: Onetime::CustomDomain::Lookup.found(domain.display_domain, domain),
    })
  end
  let!(:config) do
    Onetime::CustomDomain::IncomingConfig.create!(
      domain_id: domain.identifier, enabled: true, recipients: [{ email: recipient, name: 'Help' }],
      passphrase_required: true, max_ttl: 120, email_disabled: true, post_url: 'https://hooks.example.net/incoming',
    )
  end

  before do
    allow_any_instance_of(Incoming::Logic::CreateIncomingSecret).to receive(:enforce_incoming_rate_limit!)
    organization.replace_sharing_policy!(organization.sharing_policy.merge('recipient_email_mode' => 'disabled', 'max_ttl' => 60))
  end

  after do
    config.destroy!
    domain.destroy!
    organization.destroy!
    owner.destroy!
  end

  def public_config
    logic = Incoming::Logic::GetConfig.new(strategy, {})
    logic.raise_concerns
    logic.process.fetch(:config)
  end

  def incoming_secret(passphrase)
    Incoming::Logic::CreateIncomingSecret.new(strategy, {
      'secret' => { 'secret' => 'confidential', 'recipient' => config.public_recipients.first.fetch('digest'),
                    'passphrase' => passphrase, 'ttl' => 604_801 },
    })
  end

  it 'returns the effective lifetime and prompt, keeping delivery settings private' do
    expect(Onetime::CustomDomain::IncomingConfig.load(domain.identifier).settings).to include(
      email_disabled: true, post_url: 'https://hooks.example.net/incoming',
    )
    expect(public_config).to include(passphrase_input_required: true, default_ttl: 60)
    expect(public_config.keys).not_to include(:post_url, :email_disabled)
  end

  it 'rejects blank or malformed required passphrases before storing a secret or queuing mail' do
    expect(Onetime::Receipt).not_to receive(:spawn_pair)
    expect(Onetime::Jobs::Publisher).not_to receive(:enqueue_email)
    [nil, '', " \t\u00a0", ['invalid']].each do |blank|
      expect { incoming_secret(blank).raise_concerns }.to raise_error(Onetime::FormError, /passphrase/i)
    end
  end

  it 'stores the clamped lifetime and passphrase and still queues email to the configured recipient' do
    logic = incoming_secret(phrase)
    expect(Onetime::Jobs::Publisher).to receive(:enqueue_email).once.with(
      :incoming_secret, hash_including(recipient: recipient, has_passphrase: true), domain_id: domain.identifier,
    )
    logic.raise_concerns
    logic.process
    stored = Onetime::Secret.load(logic.secret.identifier)
    expect(stored.passphrase?(phrase)).to be true
    expect(stored.lifespan).to eq(60)
    expect(stored.dbclient.ttl(stored.dbkey)).to be_between(58, 60)
  end

  it 'uses the Incoming lifetime when it is shorter than the organization ceiling' do
    organization.replace_sharing_policy!(organization.sharing_policy.merge('max_ttl' => 604_800))
    expect(public_config).to include(default_ttl: 120)
    expect(incoming_secret(phrase).tap(&:raise_concerns).ttl).to eq(120)
  end

  it 'requires the organization passphrase even when Incoming has no local requirement' do
    Onetime::CustomDomain::IncomingConfig.update_for_domain!(domain.identifier) do |stored|
      stored.apply_settings(passphrase_required: false)
    end
    organization.replace_sharing_policy!(organization.sharing_policy.merge('passphrase_required' => true))
    expect(public_config[:passphrase_input_required]).to be true
    expect { incoming_secret(nil).raise_concerns }.to raise_error(Onetime::FormError, /passphrase/i)
  end

  it 'uses the operator passphrase when configured and ignores a sender replacement' do
    modified_conf = YAML.load(YAML.dump(OT.conf))
    modified_conf['features']['incoming']['default_passphrase'] = 'operator passphrase'
    allow(OT).to receive(:conf).and_return(OT::Config.wrap(modified_conf))
    expect(public_config[:passphrase_input_required]).to be false
    expect(incoming_secret(phrase).tap(&:raise_concerns).passphrase).to eq('operator passphrase')
  end
end
