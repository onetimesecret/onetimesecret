# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/domains/collision_resolution'

RSpec.describe 'Collision sender pagination consumers', :datastore do
  include LegacyCustomDomainRecords

  let(:operation_class) { Onetime::Operations::Domains::CollisionResolution }
  let(:operation) { operation_class.new }
  let(:model) { Onetime::CustomDomain }
  let(:mailer_model) { Onetime::CustomDomain::MailerConfig }
  let(:suffix) { SecureRandom.hex(4) }
  let(:name) { "sender-collision-#{suffix}.example" }
  let(:other_name) { "sender-other-#{suffix}.example" }
  let(:organization) { Onetime::Organization.new(display_name: "Sender regression #{suffix}").tap(&:save) }
  let(:legacy) { {} }
  let(:strategy) { Onetime::Mail::SenderStrategies.for_provider('lettermint') }
  let(:domains_api) { double('Lettermint domains resource') }
  let(:client) { double('Lettermint client', domains: domains_api) }
  let(:sender_domain) { "sender-#{suffix}.example" }
  let(:last_page) do
    { 'data' => [{ 'domain' => sender_domain, 'id' => 'shared-remote-id' }],
      'next_cursor' => nil }
  end
  let!(:keeper_id) { sender_record(:keeper, name, verified: true) }
  let!(:victim_id) { sender_record(:victim, name) }

  before do
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::ColonelAuditEvent).to receive(:record_access)
    allow(Onetime::Mail::Mailer).to receive(:provider_credentials).with('lettermint')
      .and_return('team_token' => 'test-token')
    allow(Onetime::Mail::SenderStrategies).to receive(:for_provider).with('lettermint').and_return(strategy)
    allow(strategy).to receive(:build_client).and_return(client)
    allow(domains_api).to receive(:list).with(no_args).and_return(
      'data' => [{ 'domain' => 'unrelated.example', 'id' => 'unrelated-id' }],
      'next_cursor' => 'page-2',
    )
    allow(domains_api).to receive(:list).with(page_cursor: 'page-2').and_return(last_page)
    expect(domains_api).not_to receive(:delete)
  end

  after do
    legacy.each_value do |id, stored_name|
      mailer_model.delete_for_domain!(id)
      remove_legacy_custom_domain(id, stored_name)
    end
    organization.destroy! if organization.exists?
  end

  def sender_record(label, display_domain, verified: false)
    id = write_legacy_custom_domain(display_domain, org_id: organization.objid,
      fields: { 'ownership_verified' => verified })
    legacy[label] = [id, display_domain]
    mailer_model.create!(domain_id: id, provider: 'lettermint', from_address: "notify@#{sender_domain}")
    id
  end

  def selected_plan(*names)
    plan = operation.plan
    plan.with(groups: names.map { |selected| plan.group!(selected) })
  end

  it '[C01] applies a later-page shared target without deleting the keeper identity' do
    result = operation.apply(selected_plan(name), actor: 'cli', dry_run: false)

    expect(result.outcomes.map(&:status)).to eq([:applied])
    expect(result.outcomes.first.removals.map(&:status)).to eq([:removed])
    expect(model.find_by_identifier(victim_id)).to be_nil
    expect(mailer_model.exists_for_domain?(victim_id)).to be false
    expect(model.find_by_identifier(keeper_id)).not_to be_nil
    expect(mailer_model.exists_for_domain?(keeper_id)).to be true
    expect(domains_api).to have_received(:list).with(no_args).once
    expect(domains_api).to have_received(:list).with(page_cursor: 'page-2').once
  end

  it '[C03/C07] skips the failed group and retries the complete walk for the next group' do
    other_keeper = sender_record(:other_keeper, other_name, verified: true)
    other_victim = sender_record(:other_victim, other_name)
    attempts = 0
    allow(domains_api).to receive(:list).with(page_cursor: 'page-2') do
      attempts += 1
      raise IOError, 'temporary provider failure' if attempts == 1

      last_page
    end

    result = operation.apply(selected_plan(name, other_name), actor: 'cli', dry_run: false)

    expect(result.outcomes.map(&:status)).to eq([:skipped, :applied])
    expect(result.outcomes.first.reason).to include('lettermint lookup failed', 'retry may succeed')
    expect(result.outcomes.first.removals).to be_empty
    [keeper_id, victim_id, other_keeper].each do |id|
      expect(model.find_by_identifier(id)).not_to be_nil
      expect(mailer_model.exists_for_domain?(id)).to be true
    end
    expect(model.find_by_identifier(other_victim)).to be_nil
    expect(mailer_model.exists_for_domain?(other_victim)).to be false
    expect(domains_api).to have_received(:list).with(no_args).twice
    expect(domains_api).to have_received(:list).with(page_cursor: 'page-2').twice
  end

  it '[C08] rereads provider pages when apply follows a successful dry run on the same operation' do
    plan = selected_plan(name)
    preview = operation.apply(plan, actor: 'cli', dry_run: true)
    expect(preview.outcomes.map(&:status)).to eq([:dry_run])
    expect(preview.outcomes.first.removals.map(&:status)).to eq([:planned])
    expect(model.find_by_identifier(victim_id)).not_to be_nil
    expect(mailer_model.exists_for_domain?(victim_id)).to be true

    allow(domains_api).to receive(:list).with(page_cursor: 'page-2').and_raise(IOError, 'provider now unavailable')
    applied = operation.apply(plan, actor: 'cli', dry_run: false)

    expect(applied.outcomes.map(&:status)).to eq([:skipped])
    expect(applied.outcomes.first.reason).to include('lettermint lookup failed', 'retry may succeed')
    expect(applied.outcomes.first.removals).to be_empty
    [keeper_id, victim_id].each do |id|
      expect(model.find_by_identifier(id)).not_to be_nil
      expect(mailer_model.exists_for_domain?(id)).to be true
    end
    expect(domains_api).to have_received(:list).with(no_args).twice
    expect(domains_api).to have_received(:list).with(page_cursor: 'page-2').twice
  end
end
