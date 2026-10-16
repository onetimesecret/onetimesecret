# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/domains/collision_sender_preservation'
require 'onetime/operations/delete_sender_domain'

RSpec.describe Onetime::Operations::Domains::CollisionSenderPreservation do
  let(:keeper) { double('keeper record', domain_id: 'keeper') }
  let(:victim) { double('removal record', domain_id: 'victim') }
  let(:group) { double('collision group', keep_record: keeper, records: [keeper, victim]) }
  let(:records) { [keeper, victim] }
  let(:identity_cache) { {} }
  let(:keeper_config) { double('keeper config', effective_provider: 'ses', from_address: 'keep@example.com') }
  let(:victim_config) { double('victim config', effective_provider: 'ses', from_address: 'remove@example.com') }
  let(:keeper_domain) { double('live keeper', mailer_config: keeper_config) }
  let(:victim_domain) { double('live victim', mailer_config: victim_config) }

  before do
    allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('keeper').and_return(keeper_domain)
    allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('victim').and_return(victim_domain)
  end

  def preservation
    described_class.new(group: group, records: records, identity_cache: identity_cache).call
  end

  it 'preserves shared SES domains even with different mailbox names and no provider metadata' do
    expect(preservation).to eq('victim' => true)
    expect(Onetime::CustomDomain).to have_received(:find_by_identifier).with('keeper')
    expect(Onetime::CustomDomain).to have_received(:find_by_identifier).with('victim')
  end

  it 'reproduces the unguarded SES deletion target shared by both configs' do
    strategy = Onetime::Mail::SenderStrategies.for_provider('ses')
    client = double('SES client')
    allow(strategy).to receive(:build_ses_client).and_return(client)
    expect(client).to receive(:delete_email_identity).with(email_identity: 'example.com').twice

    [keeper_config, victim_config].each do |config|
      expect(strategy.delete_sender_identity(config, credentials: {})[:deleted]).to be true
    end
  end

  it 'normalizes DNS case for SES identity comparison' do
    allow(victim_config).to receive(:from_address).and_return('remove@EXAMPLE.COM')
    expect(preservation).to eq('victim' => true)
  end

  it 'does not preserve an independent SES identity' do
    allow(victim_config).to receive(:from_address).and_return('remove@other.example.com')
    expect(preservation).to eq('victim' => false)
  end

  it 'does not equate the same sender domain across providers' do
    allow(victim_config).to receive(:effective_provider).and_return('smtp2go')
    expect(preservation).to eq('victim' => false)
  end

  it 'reads current configs again for a new apply with a fresh cache' do
    expect(preservation).to eq('victim' => true)
    allow(victim_domain).to receive(:mailer_config).and_return(nil)
    expect(described_class.new(group: group, records: records, identity_cache: {}).call).to eq('victim' => false)
  end

  it 'excludes self by domain ID even when the audit row is a different object' do
    allow(keeper_domain).to receive(:mailer_config).and_return(nil)
    records.replace([keeper, double('audit victim row', domain_id: 'victim')])
    expect(preservation).to eq('victim' => false)
  end

  it 'caches absent configs as well as resolved identities' do
    allow(keeper_domain).to receive(:mailer_config).and_return(nil)
    2.times { expect(preservation).to eq('victim' => false) }
    expect(keeper_domain).to have_received(:mailer_config).once
    expect(victim_domain).to have_received(:mailer_config).once
  end

  [:keeper, :victim, :both].each do |missing|
    it "does not preserve an identity when #{missing} has no mailer config" do
      allow(keeper_domain).to receive(:mailer_config).and_return(nil) if [:keeper, :both].include?(missing)
      allow(victim_domain).to receive(:mailer_config).and_return(nil) if [:victim, :both].include?(missing)
      expect(preservation).to eq('victim' => false)
    end
  end

  %w[smtp logger].each do |provider|
    it "recognizes #{provider} as having no remote sender identity" do
      allow(victim_config).to receive(:effective_provider).and_return(provider)
      expect(preservation).to eq('victim' => false)
    end
  end

  [nil, '', 'unknown'].each do |provider|
    it "refuses unresolved provider #{provider.inspect}" do
      allow(victim_config).to receive(:effective_provider).and_return(provider)
      expect { preservation }.to raise_error(described_class::UnsafeIdentity)
    end
  end

  it 'refuses a malformed sender address instead of guessing an identity' do
    allow(victim_config).to receive(:from_address).and_return('invalid')
    expect { preservation }.to raise_error(described_class::UnsafeIdentity)
  end

  it 'refuses a missing live domain' do
    allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('victim').and_return(nil)
    expect { preservation }.to raise_error(described_class::UnsafeIdentity)
  end

  it 'refuses the entire group on an unreadable config, naming the record but not the underlying error' do
    allow(victim_domain).to receive(:mailer_config).and_raise(IOError, 'secret credential')
    expect { preservation }.to raise_error(described_class::UnsafeIdentity) do |error|
      expect(error.message).to eq('sender identity for victim: mailer config unreadable')
      expect(error.cause).to be_nil
    end
  end

  it 'names the record by extid when the audit row carries one' do
    allow(victim).to receive(:extid).and_return('cdvictim')
    allow(victim_config).to receive(:from_address).and_return('invalid')
    expect { preservation }.to raise_error(described_class::UnsafeIdentity, 'sender identity for cdvictim: mailer config has no sender domain')
  end

  it 'never puts the sender address or provider name from the config in the refusal' do
    allow(victim_config).to receive(:effective_provider).and_return('secret-provider')
    expect { preservation }.to raise_error(described_class::UnsafeIdentity) do |error|
      expect(error.message).to eq('sender identity for victim: mailer config names an unsupported provider')
      expect(error.message).not_to include('secret-provider', 'remove@example.com')
    end
  end

  it 'refuses a missing live domain by name' do
    allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('victim').and_return(nil)
    expect { preservation }.to raise_error(described_class::UnsafeIdentity, 'sender identity for victim: record not found')
  end

  it 'does not need other identities when no removal can delete a remote identity' do
    allow(keeper_config).to receive(:from_address).and_raise(IOError, 'secret')
    allow(victim_domain).to receive(:mailer_config).and_return(nil)
    expect(preservation).to eq('victim' => false)
    expect(keeper_config).not_to have_received(:from_address)
  end

  it 'preserves identities shared by two orphan removals in case either removal fails' do
    allow(group).to receive(:keep_record).and_return(nil)
    expect(preservation).to eq('keeper' => true, 'victim' => true)
  end

  it 'does not preserve independent orphan identities' do
    allow(group).to receive(:keep_record).and_return(nil)
    allow(keeper_config).to receive(:from_address).and_return('keep@other.example.com')
    expect(preservation).to eq('keeper' => false, 'victim' => false)
  end

  context 'references outside the selected group' do
    let(:external) { double('external audit row', domain_id: 'external') }
    let(:external_config) { double('external config', effective_provider: 'ses', from_address: 'outside@example.com') }
    let(:external_domain) { double('external domain', mailer_config: external_config) }
    let(:records) { [keeper, victim, external] }

    before do
      allow(keeper_config).to receive(:from_address).and_return('keep@independent.example.com')
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('external').and_return(external_domain)
    end

    %w[other_collision_group skipped_group unselected_group ordinary_record].each do |location|
      it "preserves a reference from #{location} regardless of selection or hostname" do
        allow(external).to receive(:category).and_return(location == 'ordinary_record' ? :ok : :collision)
        allow(external).to receive(:display_domain).and_return('unrelated.example.net')
        expect(preservation).to eq('victim' => true)
      end
    end

    it 'preserves an orphan removal identity referenced by an external survivor' do
      allow(group).to receive(:keep_record).and_return(nil)
      expect(preservation).to eq('keeper' => false, 'victim' => true)
    end

    it 'protects both removals sharing an identity even when their keeper does not share it' do
      allow(group).to receive(:records).and_return([keeper, victim, external])
      expect(preservation).to eq('victim' => true, 'external' => true)
    end

    it 'retains protection across groups after a previous removal destroys its local record' do
      expect(preservation).to eq('victim' => true)
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('victim').and_return(nil)
      next_group = double('next group', keep_record: nil, records: [external])
      expect(described_class.new(group: next_group, records: records, identity_cache: identity_cache).call)
        .to eq('external' => true)
      expect(Onetime::CustomDomain).to have_received(:find_by_identifier).with('victim').once
    end

    it 'refuses unreadable external identities instead of assuming they are independent, naming the external record' do
      allow(external_domain).to receive(:mailer_config).and_raise(IOError, 'private response')
      expect { preservation }.to raise_error(described_class::UnsafeIdentity) do |error|
        expect(error.message).to eq('sender identity for external: mailer config unreadable')
        expect(error.cause).to be_nil
      end
    end

    it 'does not hide an unreadable external identity behind a known shared match' do
      allow(keeper_config).to receive(:from_address).and_return('keep@example.com')
      allow(external_config).to receive(:effective_provider).and_return('unknown')
      expect { preservation }.to raise_error(described_class::UnsafeIdentity)
    end

    it 'does not cache a failed read as an absent identity' do
      allow(external_domain).to receive(:mailer_config).and_raise(IOError, 'private response')
      expect { preservation }.to raise_error(described_class::UnsafeIdentity)
      expect(identity_cache).not_to have_key('external')
      allow(external_domain).to receive(:mailer_config).and_return(external_config)
      expect(preservation).to eq('victim' => true)
    end
  end

  context 'SendGrid actual deletion IDs' do
    let(:strategy) { Onetime::Mail::SenderStrategies.for_provider('sendgrid') }
    let(:credentials) { { 'api_key' => 'test-token' } }
    let(:listing) { [{ 'domain' => 'example.com', 'id' => 42 }, { 'domain' => 'other.example.com', 'id' => 43 }] }

    before do
      [keeper_config, victim_config].each do |config|
        allow(config).to receive(:effective_provider).and_return('sendgrid')
      end
      allow(victim_config).to receive(:from_address).and_return('remove@other.example.com')
      allow(Onetime::Mail::Mailer).to receive(:provider_credentials).with('sendgrid').and_return(credentials)
      allow(Onetime::Mail::SenderStrategies).to receive(:for_provider).with('sendgrid').and_return(strategy)
    end

    it 'preserves a platform ID override even for different sender domains' do
      credentials['domain_id'] = 42
      expect(strategy).not_to receive(:domain_authentications)
      expect(preservation).to eq('victim' => true)
    end

    [' ', {}].each do |override|
      it "refuses a platform ID override of #{override.inspect} instead of comparing it" do
        credentials['domain_id'] = override
        expect(strategy).not_to receive(:domain_authentications)
        expect { preservation }.to raise_error(described_class::UnsafeIdentity,
          'sender identity for victim: sendgrid gave no usable identity for the sender domain')
        expect(identity_cache).not_to have_key('victim')
      end
    end

    it 'compares resolved IDs, not stored provisioning metadata' do
      allow(strategy).to receive(:domain_authentications).with(api_key: 'test-token').and_return(listing)
      expect(preservation).to eq('victim' => false)
    end

    it 'preserves matching provider IDs' do
      listing.last['id'] = 42
      allow(strategy).to receive(:domain_authentications).with(api_key: 'test-token').and_return(listing)
      expect(preservation).to eq('victim' => true)
    end

    it 'lists the account domains once per apply, however many records are audited' do
      allow(strategy).to receive(:domain_authentications).with(api_key: 'test-token').and_return(listing)
      others = Array.new(5) do |i|
        config = double("config #{i}", effective_provider: 'sendgrid', from_address: "mail@tenant#{i}.example.net")
        allow(Onetime::CustomDomain).to receive(:find_by_identifier).with("other#{i}").and_return(double("live #{i}", mailer_config: config))
        listing << { 'domain' => "tenant#{i}.example.net", 'id' => 100 + i }
        double("other record #{i}", domain_id: "other#{i}")
      end
      records.concat(others)
      2.times { expect(preservation).to eq('victim' => false) }
      expect(strategy).to have_received(:domain_authentications).once
      expect(identity_cache.keys.grep(String)).to match_array(%w[keeper victim] + others.map(&:domain_id))
    end

    it 'treats a sender domain absent from the complete listing as no identity, as deletion does' do
      allow(strategy).to receive(:domain_authentications).and_return(listing.first(1))
      allow(strategy).to receive(:each_domain_authentication_page).and_yield(listing.first(1)).and_return(true)

      expect(preservation).to eq('victim' => false)
      # Nothing to share, so the keeper is never resolved.
      expect(identity_cache).to include('victim' => nil)
      expect(identity_cache).not_to have_key('keeper')
      expect(strategy.send(:find_domain_id, 'other.example.com', api_key: 'test-token')).to be_nil
    end

    it 'does not share an identity with a keeper the provider does not list' do
      allow(strategy).to receive(:domain_authentications).and_return(listing.last(1))
      expect(preservation).to eq('victim' => false)
      expect(identity_cache).to include('keeper' => nil, 'victim' => %w[sendgrid 43])
    end

    it 'refuses a failed listing as a retryable provider failure and lists again next time' do
      allow(strategy).to receive(:domain_authentications).and_return(nil, listing)
      expect { preservation }.to raise_error(described_class::UnsafeIdentity) do |error|
        expect(error.message).to eq('sender identity for victim: sendgrid lookup failed; the provider did not answer or refused the request, retry may succeed')
        expect(error.cause).to be_nil
      end
      expect(identity_cache).not_to have_key([:listing, 'sendgrid'])
      expect(preservation).to eq('victim' => false)
      expect(strategy).to have_received(:domain_authentications).twice
    end
  end

  context 'Lettermint paginated deletion targets' do
    let(:strategy) { Onetime::Mail::SenderStrategies.for_provider('lettermint') }
    let(:domains_api) { double('Lettermint domains resource') }
    let(:client) { double('Lettermint client', domains: domains_api) }
    let(:target) { { 'domain' => 'example.com', 'id' => 'shared-remote-id' } }
    let(:first_page) { domain_page([{ 'domain' => 'unrelated.example', 'id' => 'unrelated-id' }], 'page-2') }
    let(:last_page) { domain_page([target]) }

    before do
      [keeper_config, victim_config].each do |config|
        allow(config).to receive(:effective_provider).and_return('lettermint')
      end
      allow(Onetime::Mail::Mailer).to receive(:provider_credentials).with('lettermint')
        .and_return('team_token' => 'test-token')
      allow(Onetime::Mail::SenderStrategies).to receive(:for_provider).with('lettermint').and_return(strategy)
      allow(strategy).to receive(:build_client).and_return(client)
      allow(domains_api).to receive(:list).with(no_args).and_return(first_page)
      allow(domains_api).to receive(:list).with(page_cursor: 'page-2').and_return(last_page)
    end

    def domain_page(entries, next_cursor = nil)
      { 'data' => entries, 'next_cursor' => next_cursor }
    end

    def expect_retryable_listing_refusal
      expect { preservation }.to raise_error(described_class::UnsafeIdentity) do |error|
        expect(error.message).to eq('sender identity for victim: lettermint lookup failed; the provider did not answer or refused the request, retry may succeed')
        expect(error.cause).to be_nil
      end
      expect(identity_cache).not_to have_key([:listing, 'lettermint'])
      expect(identity_cache).not_to have_key('victim')
    end

    it '[C01] preserves a shared later-page target resolved by the real deletion lookup' do
      expect(preservation).to eq('victim' => true)
      expect(identity_cache).to include('keeper' => ['lettermint', target['id']], 'victim' => ['lettermint', target['id']])
      expect(domains_api).to have_received(:list).with(no_args).once
      expect(domains_api).to have_received(:list).with(page_cursor: 'page-2').once

      expect(strategy.send(:find_domain_by_name, client, 'example.com')).to eq(target)
      expect(domains_api).to have_received(:list).with(page_cursor: 'page-2').twice
    end

    it '[C02] accepts absence only after walking the complete listing, as deletion does' do
      allow(victim_config).to receive(:from_address).and_return('remove@absent.example')

      expect(preservation).to eq('victim' => false)
      expect(identity_cache).to include('victim' => nil)
      expect(identity_cache).not_to have_key('keeper')
      expect(domains_api).to have_received(:list).with(page_cursor: 'page-2').once
      expect(strategy.send(:find_domain_by_name, client, 'absent.example')).to be_nil
    end

    {
      'missing data' => { 'next_cursor' => nil },
      'non-array data' => { 'data' => {}, 'next_cursor' => nil },
      'missing next_cursor' => { 'data' => [] },
      'nested-only next_cursor' => { 'data' => [], 'meta' => { 'next_cursor' => nil } },
      'invalid cursor' => { 'data' => [], 'next_cursor' => 42 },
    }.each do |label, malformed|
      it "[C03] refuses and does not cache a later page with #{label}" do
        allow(domains_api).to receive(:list).with(page_cursor: 'page-2').and_return(malformed)
        expect_retryable_listing_refusal

        allow(domains_api).to receive(:list).with(page_cursor: 'page-2').and_return(last_page)
        expect(preservation).to eq('victim' => true)
        expect(domains_api).to have_received(:list).with(no_args).twice
        expect(domains_api).to have_received(:list).with(page_cursor: 'page-2').twice
      end
    end

    it '[C03/C14] refuses a later-page transport failure even when the target was on the first page' do
      allow(domains_api).to receive(:list).with(no_args).and_return(domain_page([target], 'page-2'))
      allow(domains_api).to receive(:list).with(page_cursor: 'page-2').and_raise(IOError, 'secret response test-token')
      expect_retryable_listing_refusal
    end

    it '[C03] refuses a cursor cycle without issuing an unbounded list walk' do
      allow(domains_api).to receive(:list).with(page_cursor: 'page-2').and_return(domain_page([target], 'page-3'))
      allow(domains_api).to receive(:list).with(page_cursor: 'page-3').and_return(domain_page([], 'page-2'))
      expect_retryable_listing_refusal
      expect(domains_api).to have_received(:list).with(no_args).once
      expect(domains_api).to have_received(:list).with(page_cursor: 'page-2').once
      expect(domains_api).to have_received(:list).with(page_cursor: 'page-3').once
    end

    it '[C06] reuses one complete walk across 1000 records and multiple groups' do
      allow(victim_config).to receive(:from_address).and_return('remove@other.example.com')
      entries = [target, { 'domain' => 'other.example.com', 'id' => target['id'] }]
      others = Array.new(998) do |i|
        config = double("config #{i}", effective_provider: 'lettermint', from_address: "mail@tenant#{i}.example.net")
        allow(Onetime::CustomDomain).to receive(:find_by_identifier).with("other#{i}")
          .and_return(double("live #{i}", mailer_config: config))
        entries << { 'domain' => "tenant#{i}.example.net", 'id' => "remote-#{i}" }
        double("record #{i}", domain_id: "other#{i}")
      end
      records.concat(others)
      allow(domains_api).to receive(:list).with(no_args).and_return(domain_page(entries.first(400), 'page-2'))
      allow(domains_api).to receive(:list).with(page_cursor: 'page-2').and_return(domain_page(entries.slice(400, 400), 'page-3'))
      allow(domains_api).to receive(:list).with(page_cursor: 'page-3').and_return(domain_page(entries.drop(800)))

      expect(preservation).to eq('victim' => true)
      second_group = double('second group', keep_record: others.first, records: others.first(2))
      expect(described_class.new(group: second_group, records: records, identity_cache: identity_cache).call)
        .to eq('other1' => false)
      expect(identity_cache.keys.grep(String).size).to eq(1000)
      expect(domains_api).to have_received(:list).with(no_args).once
      ['page-2', 'page-3'].each do |cursor|
        expect(domains_api).to have_received(:list).with(page_cursor: cursor).once
      end
      expect(strategy).to have_received(:build_client).once
      records.each do |record|
        expect(Onetime::CustomDomain).to have_received(:find_by_identifier).with(record.domain_id).once
      end
    end

    it '[C07] retries a failed complete walk for the next group sharing the apply cache' do
      allow(domains_api).to receive(:list).with(page_cursor: 'page-2').and_raise(IOError, 'temporary failure')
      expect_retryable_listing_refusal
      allow(domains_api).to receive(:list).with(page_cursor: 'page-2').and_return(last_page)
      second_group = double('next group', keep_record: victim, records: [keeper, victim])

      expect(described_class.new(group: second_group, records: records, identity_cache: identity_cache).call)
        .to eq('keeper' => true)
      expect(identity_cache).to include('keeper' => ['lettermint', target['id']], 'victim' => ['lettermint', target['id']])
      expect(domains_api).to have_received(:list).with(no_args).twice
      expect(domains_api).to have_received(:list).with(page_cursor: 'page-2').twice
    end
  end

  context 'Lettermint actual deletion IDs' do
    let(:strategy) { Onetime::Mail::SenderStrategies.for_provider('lettermint') }
    let(:client) { double('Lettermint client') }
    let(:listing) { [{ 'domain' => 'example.com', 'id' => 'remote-1' }, { 'domain' => 'other.example.com', 'id' => 'remote-2' }] }

    before do
      [keeper_config, victim_config].each do |config|
        allow(config).to receive(:effective_provider).and_return('lettermint')
      end
      allow(Onetime::Mail::Mailer).to receive(:provider_credentials).with('lettermint')
        .and_return('team_token' => 'test-token')
      allow(Onetime::Mail::SenderStrategies).to receive(:for_provider).with('lettermint').and_return(strategy)
      allow(strategy).to receive(:build_client).and_return(client)
    end

    it 'preserves the ID resolved through the same domain list as deletion' do
      allow(strategy).to receive(:list_domains).with(client).and_return(listing)
      expect(preservation).to eq('victim' => true)
    end

    it 'does not preserve different remote IDs' do
      allow(victim_config).to receive(:from_address).and_return('remove@other.example.com')
      allow(strategy).to receive(:list_domains).with(client).and_return(listing)
      expect(preservation).to eq('victim' => false)
    end

    it 'lists the account domains once per apply and builds one client' do
      allow(strategy).to receive(:list_domains).with(client).and_return(listing)
      2.times { expect(preservation).to eq('victim' => true) }
      expect(strategy).to have_received(:list_domains).once
      expect(strategy).to have_received(:build_client).once
    end

    it 'refuses an unavailable provider as a retryable lookup failure, without its response' do
      allow(strategy).to receive(:list_domains).and_raise(IOError, 'secret response')
      expect { preservation }.to raise_error(described_class::UnsafeIdentity) do |error|
        expect(error.message).to eq('sender identity for victim: lettermint lookup failed; the provider did not answer or refused the request, retry may succeed')
        expect(error.message).not_to include('secret response', 'test-token', 'example.com')
        expect(error.cause).to be_nil
      end
    end

    it 'refuses a listing without data as a retryable lookup failure' do
      allow(strategy).to receive(:list_domains).and_return(nil)
      expect { preservation }.to raise_error(described_class::UnsafeIdentity, 'sender identity for victim: lettermint lookup failed; the provider did not answer or refused the request, retry may succeed')
    end

    it 'treats a sender domain absent from the listing as no identity, as deletion does' do
      allow(victim_config).to receive(:from_address).and_return('remove@unlisted.example.com')
      domains_api = double('Lettermint domains resource')
      allow(client).to receive(:domains).and_return(domains_api)
      allow(domains_api).to receive(:list).with(no_args)
        .and_return('data' => listing, 'next_cursor' => nil)

      expect(preservation).to eq('victim' => false)
      expect(identity_cache).to include('victim' => nil)
      expect(identity_cache).not_to have_key('keeper')
      expect(strategy.send(:find_domain_by_name, client, 'unlisted.example.com')).to be_nil
    end

    it '[C03/C14] refuses a listed sender domain without a provider ID through the real inventory validation' do
      domains_api = double('Lettermint domains resource')
      allow(client).to receive(:domains).and_return(domains_api)
      allow(domains_api).to receive(:list).with(no_args)
        .and_return('data' => [{ 'domain' => 'example.com' }], 'next_cursor' => nil)

      expect { preservation }.to raise_error(described_class::UnsafeIdentity) do |error|
        expect(error.message).to eq('sender identity for victim: lettermint lookup failed; the provider did not answer or refused the request, retry may succeed')
        expect(error.cause).to be_nil
      end
      expect(identity_cache).not_to have_key([:listing, 'lettermint'])
      expect(identity_cache).not_to have_key('victim')
      expect(domains_api).to have_received(:list).with(no_args).once
    end

    it 'reports unreadable installation credentials as a local failure, not a provider one' do
      allow(Onetime::Mail::Mailer).to receive(:provider_credentials).with('lettermint').and_raise(IOError, 'vault down')
      expect(strategy).not_to receive(:build_client)
      expect { preservation }.to raise_error(described_class::UnsafeIdentity) do |error|
        expect(error.message).to eq('sender identity for victim: lettermint installation credentials unreadable')
        expect(error.cause).to be_nil
      end
    end

    it 'refuses missing installation credentials by key name, without contacting the provider' do
      allow(Onetime::Mail::Mailer).to receive(:provider_credentials).with('lettermint').and_return({})
      expect(strategy).not_to receive(:build_client)
      expect { preservation }.to raise_error(described_class::UnsafeIdentity, 'sender identity for victim: lettermint credentials have no team_token; the identity cannot be resolved')
    end
  end
end
