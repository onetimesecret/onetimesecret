# spec/unit/onetime/models/custom_domain/chores/remove_orphaned_approximated_vhosts_spec.rb
#
# frozen_string_literal: true

# Unit tests for the remove_orphaned_approximated_vhosts housekeeping chore.
#
# Follows migrate_incoming_secrets_to_config_spec.rb: no datastore, no
# network. Every collaborator is injected through the chore's constructor:
#
#   client:   class_double(ApproximatedClient) returning
#             instance_double(HTTParty::Response), so stubs cannot drift from
#             the real API surface
#   resolver: instance_double(DnsLookup) answering from a Hash of snapshots
#   features: class_double(DomainValidation::Features)
#   record:   an UNSAVED Onetime::CustomDomain with save_fields / save stubbed.
#             A real instance (rather than a double) keeps parse_vhost and the
#             field setters real, which the idempotency and "state kept"
#             assertions depend on.
#
# The default world below is one where the chore WOULD delete: strategy moved
# to caddy_on_demand, API key set, DNS points outside the cluster, apply mode
# on, Approximated reports the vhost idle, DELETE answers 200. Each guard
# example flips exactly one of those and asserts nothing was deleted, so the
# guard under test is the only thing standing between the record and a DELETE.
#
# Run: tests/lanes/run unit --only spec/unit/onetime/models/custom_domain/chores/remove_orphaned_approximated_vhosts_spec.rb

require 'spec_helper'
require 'net/http'
require 'socket'

# Load the chore registration
require_relative '../../../../../../lib/onetime/models/custom_domain/chores/remove_orphaned_approximated_vhosts'
require_relative '../../../../../../lib/onetime/jobs/scheduled/housekeeping_job'

RSpec.describe Onetime::Chores::RemoveOrphanedApproximatedVhosts do
  let(:chore_name) { :remove_orphaned_approximated_vhosts }
  let(:apply_env) { described_class::APPLY_ENV }

  # Distinctive so the secrecy examples cannot pass by accident.
  let(:api_key) { 'apx-key-DO-NOT-LOG-5f2c81d9' }

  let(:display_domain) { 'secrets.example.com' }
  let(:cluster_ip) { '203.0.113.10' }
  let(:elsewhere_ip) { '198.51.100.7' }

  # --- config / features -------------------------------------------------
  let(:strategy) { 'caddy_on_demand' }
  let(:config) { { 'features' => { 'domains' => { 'validation_strategy' => strategy } } } }
  let(:proxy_ip) { cluster_ip }
  let(:proxy_host) { nil }
  let(:features_approximated) { false }
  let(:features) do
    class_double(
      Onetime::DomainValidation::Features,
      api_key: api_key,
      proxy_ip: proxy_ip,
      proxy_host: proxy_host,
      approximated?: features_approximated,
    )
  end

  # --- DNS -----------------------------------------------------------------
  let(:dns_answers) { { display_domain => snapshot([elsewhere_ip]) } }
  let(:resolver) { instance_double(described_class::DnsLookup) }

  # --- Approximated API ------------------------------------------------------
  let(:idle_data) do
    { 'incoming_address' => display_domain, 'status' => 'ACTIVE_SSL', 'is_resolving' => false, 'apx_hit' => false }
  end
  let(:live_data) { idle_data }
  # A response, or an exception instance to raise.
  let(:get_result) { api_response(200, { 'data' => live_data }) }
  let(:delete_result) { api_response(200, { 'success' => true }) }
  let(:client) { class_double(Onetime::DomainValidation::ApproximatedClient) }

  # --- pacing / mode -------------------------------------------------------
  let(:sleeps) { [] }
  let(:sleeper) { ->(seconds) { sleeps << seconds } }
  let(:pause) { 0.5 }
  let(:apply) { true }

  let(:chore) do
    described_class.new(
      client: client,
      resolver: resolver,
      features: features,
      config: config,
      apply: apply,
      pause: pause,
      sleeper: sleeper,
    )
  end

  # --- record ----------------------------------------------------------------
  let(:stored_vhost) { { 'id' => 4242, 'incoming_address' => display_domain, 'status' => 'ACTIVE_SSL' } }
  let(:vhost) { JSON.generate(stored_vhost) }
  let(:old_timestamp) { 1_700_000_000 }
  let(:saved_fields) { [] }
  let(:domain) { build_domain(display_domain, vhost) }

  # --- logging -----------------------------------------------------------------
  let(:log_lines) { [] }
  let(:logger) do
    instance_double(SemanticLogger::Logger).tap do |dbl|
      [:debug, :info, :warn, :error].each do |level|
        allow(dbl).to receive(level) do |message = nil, payload = nil|
          log_lines << [level, message, payload]
          true
        end
      end
    end
  end

  let(:frozen_now) { 1_800_000_123.75 }

  # Fields the chore must never change, in memory or in the datastore.
  ownership_field_names = [
    :verified, :verified_by_override, :resolving, :txt_validation_host, :txt_validation_value, :status
  ].freeze

  define_method(:ownership_fields) do |record|
    ownership_field_names.to_h { |field| [field, record.public_send(field)] }
  end

  def snapshot(addresses, cnames = [])
    described_class::DnsLookup::Snapshot.new(addresses: addresses, cnames: cnames)
  end

  def api_response(code, body = nil)
    instance_double(
      HTTParty::Response,
      code: code,
      success?: (200..299).cover?(code),
      parsed_response: body,
    )
  end

  # Same construction ApproximatedClient.handle_error_response uses.
  def response_error(message)
    HTTParty::ResponseError.new(message)
  end

  def not_found_error(name = display_domain)
    response_error("Could not find Virtual Host: #{name}")
  end

  # CustomDomain#init parses display_domain and raises on a blank one, so the
  # record is built with a valid name and the name under test assigned after.
  def build_domain(name, vhost_value, saved: saved_fields)
    Onetime::CustomDomain.new(
      display_domain: 'placeholder.example.com',
      vhost: vhost_value,
      vhost_fetch_failed_at: old_timestamp,
      updated: old_timestamp,
      verified: true,
      verified_by_override: true,
      resolving: true,
      txt_validation_host: '_onetime-challenge-abc123',
      txt_validation_value: 'txt-value-def456',
      status: 'active',
    ).tap do |record|
      record.display_domain = name
      allow(record).to receive(:save_fields) do |*fields|
        saved << fields
        true
      end
      allow(record).to receive(:save).and_return(true)
    end
  end

  def result_or_raise(result)
    raise result if result.is_a?(Exception)

    result
  end

  def call_swallowing_errors(record = domain)
    chore.call(record)
  rescue StandardError => ex
    ex
  end

  def logged(level)
    log_lines.select { |line| line[0] == level }
  end

  around do |example|
    saved_env = ENV.fetch(described_class::APPLY_ENV, nil)
    ENV.delete(described_class::APPLY_ENV)
    example.run
  ensure
    if saved_env.nil?
      ENV.delete(described_class::APPLY_ENV)
    else
      ENV[described_class::APPLY_ENV] = saved_env
    end
  end

  before do
    allow(Onetime).to receive(:get_logger).and_call_original
    allow(Onetime).to receive(:get_logger).with('Chores').and_return(logger)
    allow(OT).to receive(:now).and_return(frozen_now)

    allow(resolver).to receive(:lookup) { |host| dns_answers.fetch(host) { snapshot([]) } }
    allow(client).to receive(:get_vhost_by_incoming_address) { |*_args| result_or_raise(get_result) }
    allow(client).to receive(:delete_vhost) { |*_args| result_or_raise(delete_result) }
  end

  # ------------------------------------------------------------------------
  # Shared examples
  # ------------------------------------------------------------------------

  shared_examples 'ownership fields untouched' do
    it 'never changes or persists verified, verified_by_override, resolving, TXT fields or status' do
      before_call = ownership_fields(domain)
      expect(before_call.values).to all(satisfy { |value| !value.nil? && value != false })

      call_swallowing_errors

      expect(ownership_fields(domain)).to eq(before_call)
      expect(saved_fields.flatten - [:vhost, :vhost_fetch_failed_at, :updated]).to be_empty
      expect(domain).not_to have_received(:save)
    end
  end

  shared_examples 'local vhost state kept' do
    it 'keeps vhost, vhost_fetch_failed_at and updated, and writes nothing' do
      call_swallowing_errors

      expect(domain.vhost).to eq(vhost)
      expect(domain.vhost_fetch_failed_at).to eq(old_timestamp)
      expect(domain.updated).to eq(old_timestamp)
      expect(domain).not_to have_received(:save_fields)
      expect(domain).not_to have_received(:save)
    end
  end

  shared_examples 'no Approximated API call' do
    it 'calls neither GET nor DELETE and never sleeps' do
      call_swallowing_errors

      expect(client).not_to have_received(:get_vhost_by_incoming_address)
      expect(client).not_to have_received(:delete_vhost)
      expect(sleeps).to be_empty
    end
  end

  shared_examples 'no DNS lookup' do
    it 'does not resolve anything' do
      call_swallowing_errors
      expect(resolver).not_to have_received(:lookup)
    end
  end

  shared_examples 'no DELETE' do
    it 'does not delete the remote vhost' do
      call_swallowing_errors
      expect(client).not_to have_received(:delete_vhost)
    end
  end

  # A guard that stops the chore before any Approximated API call.
  shared_examples 'a skip before the API' do
    it 'returns nil' do
      expect(chore.call(domain)).to be_nil
    end

    include_examples 'local vhost state kept'
    include_examples 'no Approximated API call'
    include_examples 'ownership fields untouched'
  end

  shared_examples 'local vhost state cleared' do
    it 'returns true' do
      expect(chore.call(domain)).to be true
    end

    it 'clears vhost and vhost_fetch_failed_at and refreshes updated' do
      chore.call(domain)

      expect(domain.vhost).to be_nil
      expect(domain.vhost_fetch_failed_at).to be_nil
      expect(domain.updated).to eq(frozen_now.to_i)
      expect(domain.updated).not_to eq(old_timestamp)
    end

    it 'persists exactly vhost, vhost_fetch_failed_at and updated via save_fields, never save' do
      chore.call(domain)

      expect(saved_fields).to eq([[:vhost, :vhost_fetch_failed_at, :updated]])
      expect(domain).not_to have_received(:save)
    end

    include_examples 'ownership fields untouched'
  end

  shared_examples 'a CleanupFailed error' do |message_pattern|
    it 'raises CleanupFailed' do
      expect { chore.call(domain) }.to raise_error(described_class::CleanupFailed, message_pattern)
    end

    it 'is a StandardError, so HousekeepingJob counts it and continues' do
      expect(described_class::CleanupFailed.ancestors).to include(StandardError)
    end

    include_examples 'local vhost state kept'
    include_examples 'ownership fields untouched'
  end

  # ------------------------------------------------------------------------
  # Registration
  # ------------------------------------------------------------------------

  describe 'chore registration' do
    let(:registered) { Onetime::CustomDomain.chores[chore_name] }

    it 'is registered on Onetime::CustomDomain as an instance of the class' do
      expect(Onetime::CustomDomain.chores).to have_key(chore_name)
      expect(registered).to be_an_instance_of(described_class)
      expect(described_class::CHORE_NAME).to eq(chore_name)
    end

    it 'is callable with one record' do
      expect(registered).to respond_to(:call)
      expect(registered.method(:call).arity).to eq(1)
    end

    # The nightly HousekeepingJob runs this instance. It must not have been
    # constructed in apply mode: nil defers to the environment variable.
    it 'is registered without an explicit apply flag' do
      expect(registered.instance_variable_get(:@apply)).to be_nil
    end

    it 'accepts only the literal value "apply" from the environment' do
      expect(described_class::APPLY_ENV).to eq('APPROXIMATED_VHOST_CLEANUP')
      expect(described_class::APPLY_VALUE).to eq('apply')
    end
  end

  # ------------------------------------------------------------------------
  # Default world sanity: proves the guard examples are not vacuous
  # ------------------------------------------------------------------------

  describe 'default world (every guard open)' do
    it 'checks the live vhost and then deletes it by API key and domain' do
      chore.call(domain)

      expect(client).to have_received(:get_vhost_by_incoming_address).with(api_key, display_domain).once
      expect(client).to have_received(:delete_vhost).with(api_key, display_domain).once
    end

    it 'resolves only the display domain when no proxy_host is configured' do
      chore.call(domain)
      expect(resolver).to have_received(:lookup).with(display_domain).once
    end

    it 'logs the removal at info with the domain and remote outcome' do
      chore.call(domain)

      expect(logged(:info)).to contain_exactly(
        [:info, 'Removed orphaned Approximated vhost',
         hash_including(chore: chore_name, domain: display_domain, domain_extid: domain.extid, remote: 'deleted')],
      )
    end

    include_examples 'local vhost state cleared'
  end

  # ------------------------------------------------------------------------
  # Guard 1: vhost state
  # ------------------------------------------------------------------------

  describe '#vhost_state?' do
    {
      'nil' => [nil, false],
      'empty string' => ['', false],
      'whitespace' => ['   ', false],
      'empty JSON object' => ['{}', false],
      'padded empty JSON object' => [" {}\n", false],
      'JSON null' => ['null', false],
      'empty Hash' => [{}, false],
      'non-empty Hash' => [{ 'id' => 1 }, true],
      'JSON object string' => ['{"id":1,"incoming_address":"secrets.example.com"}', true],
      'JSON array string' => ['[1]', true],
      'garbage string' => ['not-json-at-all', true],
    }.each do |label, (value, expected)|
      it "is #{expected} for #{label}" do
        expect(chore.vhost_state?(build_domain(display_domain, value))).to be(expected)
      end
    end
  end

  describe 'no vhost state (silent skip)' do
    [nil, '', '   ', '{}', 'null', {}].each do |value|
      context "when vhost is #{value.inspect}" do
        let(:vhost) { value }

        it 'returns nil' do
          expect(chore.call(domain)).to be_nil
        end

        it 'logs nothing' do
          chore.call(domain)
          expect(log_lines).to be_empty
        end

        it 'reads neither config, features, DNS nor the API' do
          chore.call(domain)

          expect(resolver).not_to have_received(:lookup)
          expect(client).not_to have_received(:get_vhost_by_incoming_address)
          expect(client).not_to have_received(:delete_vhost)
          expect(features).not_to have_received(:api_key)
          expect(features).not_to have_received(:approximated?)
          expect(sleeps).to be_empty
        end

        it 'writes nothing' do
          chore.call(domain)

          expect(domain).not_to have_received(:save_fields)
          expect(domain).not_to have_received(:save)
          expect(domain.vhost_fetch_failed_at).to eq(old_timestamp)
        end

        include_examples 'ownership fields untouched'
      end
    end
  end

  describe 'vhost state that does not parse' do
    before { allow(OT).to receive(:le) } # CustomDomain#parse_vhost reports the bad JSON

    context 'when vhost is a garbage string' do
      let(:vhost) { 'not-json-at-all' }

      it 'still counts as Approximated-era state and is deleted by display_domain' do
        expect(chore.call(domain)).to be true
        expect(client).to have_received(:delete_vhost).with(api_key, display_domain)
        expect(domain.vhost).to be_nil
      end
    end

    context 'when vhost is a non-empty Hash without incoming_address' do
      let(:vhost) { { 'id' => 4242 } }

      it 'proceeds to the delete' do
        expect(chore.call(domain)).to be true
        expect(client).to have_received(:delete_vhost).with(api_key, display_domain)
      end
    end
  end

  # ------------------------------------------------------------------------
  # Guard 2: display_domain
  # ------------------------------------------------------------------------

  describe 'blank display_domain' do
    [nil, '', '   '].each do |value|
      context "when display_domain is #{value.inspect}" do
        let(:domain) { build_domain(value, vhost) }

        it 'logs the skip at debug' do
          chore.call(domain)
          expect(log_lines).to eq(
            [[:debug, 'Skipping: record has no display_domain',
              { chore: chore_name, domain: value, domain_extid: domain.extid }]],
          )
        end

        include_examples 'a skip before the API'
        include_examples 'no DNS lookup'
      end
    end
  end

  describe 'display_domain normalization' do
    let(:domain) { build_domain('  Secrets.Example.COM ', vhost) }

    it 'resolves and deletes by the stripped, lowercased name' do
      expect(chore.call(domain)).to be true

      expect(resolver).to have_received(:lookup).with(display_domain)
      expect(client).to have_received(:get_vhost_by_incoming_address).with(api_key, display_domain)
      expect(client).to have_received(:delete_vhost).with(api_key, display_domain)
    end
  end

  # ------------------------------------------------------------------------
  # Guard 3: strategy
  # ------------------------------------------------------------------------

  describe '#strategy_permits_cleanup?' do
    ['approximated', 'Approximated', 'APPROXIMATED', '  approximated  ', nil, '', '   '].each do |value|
      context "when validation_strategy is #{value.inspect}" do
        let(:strategy) { value }

        it 'is false' do
          expect(chore.strategy_permits_cleanup?).to be false
        end

        it 'logs the skip at debug' do
          chore.call(domain)
          expect(logged(:debug).map { |line| line[1] })
            .to eq(['Skipping: system strategy is approximated or not set'])
        end

        include_examples 'a skip before the API'
        include_examples 'no DNS lookup'
      end
    end

    %w[caddy_on_demand caddy passthrough Caddy_On_Demand].each do |value|
      context "when validation_strategy is #{value.inspect}" do
        let(:strategy) { value }

        it 'is true and the vhost is deleted' do
          expect(chore.strategy_permits_cleanup?).to be true
          expect(chore.call(domain)).to be true
          expect(client).to have_received(:delete_vhost).with(api_key, display_domain)
        end
      end
    end

    context 'when the config has no features.domains section' do
      let(:config) { { 'features' => {} } }

      it 'is false (no passthrough default)' do
        expect(chore.strategy_permits_cleanup?).to be false
      end

      include_examples 'a skip before the API'
    end

    context 'when the config says caddy but Features still reports approximated' do
      let(:features_approximated) { true }

      it 'is false' do
        expect(chore.strategy_permits_cleanup?).to be false
        expect(features).to have_received(:approximated?)
      end

      include_examples 'a skip before the API'
      include_examples 'no DNS lookup'
    end

    context 'when no config is injected' do
      let(:config) { nil }

      it 'reads OT.conf: approximated blocks' do
        allow(OT).to receive(:conf)
          .and_return({ 'features' => { 'domains' => { 'validation_strategy' => 'approximated' } } })

        expect(chore.strategy_permits_cleanup?).to be false
        expect(chore.call(domain)).to be_nil
        expect(client).not_to have_received(:delete_vhost)
      end

      it 'reads OT.conf: caddy_on_demand permits' do
        allow(OT).to receive(:conf)
          .and_return({ 'features' => { 'domains' => { 'validation_strategy' => 'caddy_on_demand' } } })

        expect(chore.strategy_permits_cleanup?).to be true
      end

      it 'fails closed when OT.conf is not loaded' do
        allow(OT).to receive(:conf).and_return(nil)
        expect(chore.strategy_permits_cleanup?).to be false
      end
    end
  end

  # ------------------------------------------------------------------------
  # Guard 4: API key
  # ------------------------------------------------------------------------

  describe '#api_key_configured?' do
    [nil, '', '   '].each do |value|
      context "when the API key is #{value.inspect}" do
        let(:api_key) { value }

        it 'is false' do
          expect(chore.api_key_configured?).to be false
        end

        it 'logs the skip at debug' do
          chore.call(domain)
          expect(logged(:debug).map { |line| line[1] }).to eq(['Skipping: no Approximated API key configured'])
        end

        include_examples 'a skip before the API'
        include_examples 'no DNS lookup'
      end
    end

    it 'is true for a non-blank key' do
      expect(chore.api_key_configured?).to be true
    end
  end

  # ------------------------------------------------------------------------
  # Guard 5: stored incoming_address
  # ------------------------------------------------------------------------

  describe '#vhost_matches_domain?' do
    context 'when incoming_address is absent' do
      let(:stored_vhost) { { 'id' => 4242 } }

      it 'matches and the vhost is deleted' do
        expect(chore.vhost_matches_domain?(domain)).to be true
        expect(chore.call(domain)).to be true
      end
    end

    context 'when incoming_address is blank' do
      let(:stored_vhost) { { 'incoming_address' => '  ' } }

      it 'matches' do
        expect(chore.vhost_matches_domain?(domain)).to be true
      end
    end

    context 'when incoming_address differs only by case and padding' do
      let(:stored_vhost) { { 'incoming_address' => ' SECRETS.Example.Com ' } }

      it 'matches and the vhost is deleted' do
        expect(chore.vhost_matches_domain?(domain)).to be true
        expect(chore.call(domain)).to be true
        expect(client).to have_received(:delete_vhost).with(api_key, display_domain)
      end
    end

    context 'when the stored vhost is a Hash rather than a JSON string' do
      let(:vhost) { { 'incoming_address' => 'old-name.example.com' } }

      it 'does not match' do
        expect(chore.vhost_matches_domain?(domain)).to be false
      end
    end

    context 'when incoming_address names another hostname (renamed domain)' do
      let(:stored_vhost) { { 'id' => 4242, 'incoming_address' => 'old-name.example.com' } }

      it 'does not match' do
        expect(chore.vhost_matches_domain?(domain)).to be false
      end

      it 'logs the skip at warn, and only there' do
        chore.call(domain)

        expect(log_lines).to eq(
          [[:warn, 'Skipping: stored vhost belongs to another hostname',
            { chore: chore_name, domain: display_domain, domain_extid: domain.extid }]],
        )
      end

      it 'never sends the old hostname to the API' do
        chore.call(domain)
        expect(client).not_to have_received(:delete_vhost)
        expect(client).not_to have_received(:get_vhost_by_incoming_address)
      end

      include_examples 'a skip before the API'
      include_examples 'no DNS lookup'
    end
  end

  # ------------------------------------------------------------------------
  # Guard 6: DNS evidence
  # ------------------------------------------------------------------------

  describe '#dns_evidence' do
    shared_examples 'DNS evidence that blocks cleanup' do |expected|
      it "classifies as #{expected.inspect}" do
        expect(chore.dns_evidence(display_domain)).to eq(expected)
      end

      it 'logs the evidence at debug' do
        chore.call(domain)
        expect(log_lines).to eq(
          [[:debug, "Skipping: DNS evidence is #{expected}",
            { chore: chore_name, domain: display_domain, domain_extid: domain.extid }]],
        )
      end

      include_examples 'a skip before the API'
    end

    context 'with neither proxy_ip nor proxy_host configured' do
      let(:proxy_ip) { nil }
      let(:proxy_host) { nil }

      include_examples 'DNS evidence that blocks cleanup', :indeterminate
    end

    context 'with blank proxy_ip and proxy_host' do
      let(:proxy_ip) { '  ' }
      let(:proxy_host) { '' }

      include_examples 'DNS evidence that blocks cleanup', :indeterminate
    end

    context 'with a proxy_ip list that contains no valid address' do
      let(:proxy_ip) { 'not-an-ip, 999.1.1.1' }

      include_examples 'DNS evidence that blocks cleanup', :indeterminate
    end

    context 'when proxy_host does not resolve' do
      let(:proxy_ip) { nil }
      let(:proxy_host) { 'cluster.approximated.example' }

      include_examples 'DNS evidence that blocks cleanup', :indeterminate

      it 'does not go on to resolve the domain' do
        chore.dns_evidence(display_domain)

        expect(resolver).to have_received(:lookup).with(proxy_host)
        expect(resolver).not_to have_received(:lookup).with(display_domain)
      end
    end

    context 'when proxy_host does not resolve but proxy_ip is configured' do
      let(:proxy_host) { 'cluster.approximated.example' }

      # Fails closed: a known proxy_ip does not rescue a blind proxy_host.
      include_examples 'DNS evidence that blocks cleanup', :indeterminate
    end

    context 'when the domain has no address answer' do
      let(:dns_answers) { { display_domain => snapshot([]) } }

      include_examples 'DNS evidence that blocks cleanup', :indeterminate
    end

    context 'when the domain answers only with unparseable addresses' do
      let(:dns_answers) { { display_domain => snapshot(['garbage']) } }

      include_examples 'DNS evidence that blocks cleanup', :indeterminate
    end

    context 'when an A record matches proxy_ip' do
      let(:dns_answers) { { display_domain => snapshot([cluster_ip]) } }

      include_examples 'DNS evidence that blocks cleanup', :on_approximated
    end

    context 'when only one of several addresses is in the cluster' do
      let(:dns_answers) { { display_domain => snapshot([elsewhere_ip, cluster_ip]) } }

      include_examples 'DNS evidence that blocks cleanup', :on_approximated
    end

    context "when an address matches one of proxy_host's addresses" do
      let(:proxy_ip) { nil }
      let(:proxy_host) { 'cluster.approximated.example' }
      let(:dns_answers) do
        {
          proxy_host => snapshot(['203.0.113.20', '203.0.113.21']),
          display_domain => snapshot(['203.0.113.21']),
        }
      end

      include_examples 'DNS evidence that blocks cleanup', :on_approximated
    end

    context 'when an AAAA record matches proxy_ip in another case and compression' do
      let(:proxy_ip) { '2001:DB8:0:0:0:0:0:10' }
      let(:dns_answers) { { display_domain => snapshot(['2001:db8::10']) } }

      include_examples 'DNS evidence that blocks cleanup', :on_approximated
    end

    context 'when the domain CNAMEs to proxy_host (configured with case and trailing dot)' do
      let(:proxy_host) { 'Cluster.Approximated.Example.' }
      let(:dns_answers) do
        {
          'cluster.approximated.example' => snapshot([cluster_ip]),
          # Addresses differ from the ones we saw for proxy_host (geo / round
          # robin), so only the CNAME ties the domain to the cluster.
          display_domain => snapshot([elsewhere_ip], ['cluster.approximated.example']),
        }
      end

      include_examples 'DNS evidence that blocks cleanup', :on_approximated

      it 'looks proxy_host up lowercased and without the trailing dot' do
        chore.dns_evidence(display_domain)
        expect(resolver).to have_received(:lookup).with('cluster.approximated.example')
      end
    end

    context 'when proxy_ip lists several addresses, one of them invalid' do
      let(:proxy_ip) { "not-an-ip, #{cluster_ip} 203.0.113.11" }

      it 'does not raise and still classifies a cluster address' do
        expect(chore.classify_dns(snapshot(['203.0.113.11']), [cluster_ip, '203.0.113.11'], '')).to eq(:on_approximated)

        dns_answers[display_domain] = snapshot(['203.0.113.11'])
        expect(chore.dns_evidence(display_domain)).to eq(:on_approximated)
      end

      it 'does not raise and still classifies an outside address as moved' do
        expect(chore.dns_evidence(display_domain)).to eq(:moved)
      end
    end

    context 'when proxy_ip is an IPv4 CIDR range and the domain resolves inside it' do
      let(:proxy_ip) { '203.0.113.0/24' }
      let(:dns_answers) { { display_domain => snapshot(['203.0.113.77']) } }

      include_examples 'DNS evidence that blocks cleanup', :on_approximated
    end

    context 'when proxy_ip is an IPv4 CIDR range and the domain resolves just outside it' do
      let(:proxy_ip) { '203.0.113.0/25' }
      let(:dns_answers) { { display_domain => snapshot(['203.0.113.128']) } }

      it 'classifies as :moved and proceeds to the API' do
        expect(chore.dns_evidence(display_domain)).to eq(:moved)
        expect(chore.call(domain)).to be true
        expect(client).to have_received(:delete_vhost).with(api_key, display_domain)
      end
    end

    context 'when proxy_ip is an IPv6 CIDR range and the domain resolves inside it' do
      let(:proxy_ip) { '2001:DB8:ABCD::/48' }
      let(:dns_answers) { { display_domain => snapshot(['2001:db8:abcd:0:0:0:0:1']) } }

      include_examples 'DNS evidence that blocks cleanup', :on_approximated
    end

    context 'when proxy_ip is an IPv6 CIDR range and the domain resolves outside it' do
      let(:proxy_ip) { '2001:db8:abcd::/48' }
      let(:dns_answers) { { display_domain => snapshot(['2001:db8:abce::1']) } }

      it 'classifies as :moved' do
        expect(chore.dns_evidence(display_domain)).to eq(:moved)
      end
    end

    context 'when proxy_ip mixes a single address, a CIDR range and invalid entries' do
      let(:proxy_ip) { "#{cluster_ip}, 192.0.2.0/28 not-an-ip 10.0.0.0/99" }

      {
        'the single address' => ['203.0.113.10', :on_approximated],
        'an address inside the range' => ['192.0.2.15', :on_approximated],
        'the address after the range' => ['192.0.2.16', :moved],
        'a neighbour of the single address' => ['203.0.113.11', :moved],
      }.each do |label, (address, expected)|
        it "classifies #{label} as #{expected.inspect} without raising" do
          dns_answers[display_domain] = snapshot([address])
          expect(chore.dns_evidence(display_domain)).to eq(expected)
        end
      end
    end

    context 'when the cluster is IPv4 only and the domain answers with IPv6 as well' do
      let(:proxy_ip) { '0.0.0.0/0' }

      it 'compares within one address family and does not raise' do
        dns_answers[display_domain] = snapshot(['2001:db8::99'])
        expect(chore.dns_evidence(display_domain)).to eq(:moved)
      end

      it 'still matches the IPv4 answer' do
        dns_answers[display_domain] = snapshot(['2001:db8::99', elsewhere_ip])
        expect(chore.dns_evidence(display_domain)).to eq(:on_approximated)
      end
    end

    context "when proxy_host's addresses are combined with a proxy_ip range" do
      let(:proxy_ip) { '192.0.2.0/28' }
      let(:proxy_host) { 'cluster.approximated.example' }
      let(:dns_answers) do
        { proxy_host => snapshot(['203.0.113.20']), display_domain => snapshot(['192.0.2.3']) }
      end

      include_examples 'DNS evidence that blocks cleanup', :on_approximated
    end

    context 'when every address is outside the cluster' do
      let(:proxy_host) { 'cluster.approximated.example' }
      let(:dns_answers) do
        {
          proxy_host => snapshot(['203.0.113.20']),
          display_domain => snapshot([elsewhere_ip, '2001:db8::99'], ['edge.other-cdn.example']),
        }
      end

      it 'classifies as :moved and proceeds to the API' do
        expect(chore.dns_evidence(display_domain)).to eq(:moved)
        expect(chore.call(domain)).to be true
        expect(client).to have_received(:delete_vhost).with(api_key, display_domain)
      end
    end
  end

  describe '#classify_dns' do
    it 'is :indeterminate for an empty cluster even when the domain resolves' do
      expect(chore.classify_dns(snapshot([elsewhere_ip]), [], '')).to eq(:indeterminate)
    end

    it 'ignores CNAMEs when no proxy_host is configured' do
      expect(chore.classify_dns(snapshot([elsewhere_ip], ['']), [cluster_ip], '')).to eq(:moved)
    end

    it 'is :moved when addresses and CNAMEs are all foreign' do
      expect(chore.classify_dns(snapshot([elsewhere_ip], ['other.example']), [cluster_ip], 'cluster.example'))
        .to eq(:moved)
    end
  end

  describe 'DnsLookup#lookup' do
    let(:dns) { instance_double(Resolv::DNS) }
    let(:lookup) { described_class::DnsLookup.new }

    before do
      allow(Resolv::DNS).to receive(:open).and_yield(dns)
      allow(dns).to receive(:timeouts=)
    end

    it 'queries the rooted name and normalizes addresses and CNAMEs' do
      allow(dns).to receive(:getaddresses).with('secrets.example.com.')
        .and_return([Resolv::IPv4.create('198.51.100.7'), Resolv::IPv6.create('2001:db8::1')])
      allow(dns).to receive(:getresources)
        .with('secrets.example.com.', Resolv::DNS::Resource::IN::CNAME)
        .and_return([Resolv::DNS::Resource::IN::CNAME.new(Resolv::DNS::Name.create('Edge.Example.NET.'))])

      result = lookup.lookup(' secrets.example.com. ')

      expect(result.addresses.map(&:downcase)).to eq(['198.51.100.7', '2001:db8::1'])
      expect(result.cnames).to eq(['edge.example.net'])
      expect(dns).to have_received(:timeouts=).with(described_class::DnsLookup::TIMEOUTS)
    end

    it 'returns an empty snapshot instead of raising when the resolver fails' do
      allow(dns).to receive(:getaddresses).and_raise(Resolv::ResolvError, 'no answer')
      allow(OT).to receive(:ld)

      result = lookup.lookup('secrets.example.com')

      expect(result.addresses).to eq([])
      expect(result.cnames).to eq([])
    end
  end

  # ------------------------------------------------------------------------
  # Guard 7: dry run
  # ------------------------------------------------------------------------

  describe 'dry run' do
    shared_examples 'a dry run' do
      it 'logs the candidate at info, naming the domain and how to apply' do
        chore.call(domain)

        expect(log_lines).to eq(
          [[:info, 'Dry run: DNS has moved off Approximated; vhost is a deletion candidate',
            {
              chore: chore_name,
              domain: display_domain,
              domain_extid: domain.extid,
              apply_with: 'APPROXIMATED_VHOST_CLEANUP=apply',
            }]],
        )
      end

      it 'reaches the gate only after the DNS check' do
        chore.call(domain)
        expect(resolver).to have_received(:lookup).with(display_domain)
      end

      include_examples 'a skip before the API'
    end

    context 'with apply: false' do
      let(:apply) { false }

      include_examples 'a dry run'
    end

    context 'with apply: false while the environment says apply' do
      let(:apply) { false }

      before { ENV[apply_env] = 'apply' }

      include_examples 'a dry run'
    end

    # Only the literal `true` applies; a truthy non-boolean must not delete.
    {
      "'false'" => 'false',
      "'true'" => 'true',
      "'apply'" => 'apply',
      '1' => 1,
      ':apply' => :apply,
      'an arbitrary object' => Object.new.freeze,
    }.each do |label, value|
      context "with apply: #{label}" do
        let(:apply) { value }

        include_examples 'a dry run'
      end

      context "with apply: #{label} while the environment says apply" do
        let(:apply) { value }

        before { ENV[apply_env] = 'apply' }

        include_examples 'a dry run'
      end
    end

    context 'with apply: nil and the environment variable unset' do
      let(:apply) { nil }

      before { ENV.delete(apply_env) }

      include_examples 'a dry run'
    end

    ['true', '1', 'yes', 'APPLY', 'Apply', 'apply ', ' apply', ''].each do |value|
      context "with apply: nil and #{described_class::APPLY_ENV}=#{value.inspect}" do
        let(:apply) { nil }

        before { ENV[apply_env] = value }

        include_examples 'a dry run'
      end
    end

    context 'with apply: nil and the environment variable set to "apply"' do
      let(:apply) { nil }

      before { ENV[apply_env] = 'apply' }

      it 'deletes the vhost' do
        expect(chore.call(domain)).to be true
        expect(client).to have_received(:delete_vhost).with(api_key, display_domain).once
      end

      include_examples 'local vhost state cleared'
    end

    context 'with apply: true and the environment variable unset' do
      let(:apply) { true }

      it 'deletes the vhost' do
        expect(ENV.key?(apply_env)).to be false
        expect(chore.call(domain)).to be true
      end
    end
  end

  # ------------------------------------------------------------------------
  # Guard 8: live vhost check (apply mode)
  # ------------------------------------------------------------------------

  describe '#classify_live_vhost' do
    {
      'idle (ACTIVE_SSL, not resolving, no hits)' =>
        [{ 'status' => 'ACTIVE_SSL', 'is_resolving' => false, 'apx_hit' => false }, :idle],
      'idle without an apx_hit key' => [{ 'status' => 'PENDING', 'is_resolving' => false }, :idle],
      'ACTIVE_SSL_PROXIED even when not resolving' =>
        [{ 'status' => 'ACTIVE_SSL_PROXIED', 'is_resolving' => false, 'apx_hit' => false }, :serving],
      'is_resolving true' => [{ 'status' => 'ACTIVE_SSL', 'is_resolving' => true }, :serving],
      'apx_hit true' => [{ 'status' => 'ACTIVE_SSL', 'is_resolving' => false, 'apx_hit' => true }, :serving],
      'status UNKNOWN' => [{ 'status' => 'UNKNOWN', 'is_resolving' => false }, :indeterminate],
      'status UNKNOWN while resolving' => [{ 'status' => 'UNKNOWN', 'is_resolving' => true }, :indeterminate],
      'blank status' => [{ 'status' => '', 'is_resolving' => false }, :indeterminate],
      'missing status' => [{ 'is_resolving' => false }, :indeterminate],
      'is_resolving nil' => [{ 'status' => 'ACTIVE_SSL', 'is_resolving' => nil, 'apx_hit' => false }, :indeterminate],
      'is_resolving as the string "false"' =>
        [{ 'status' => 'ACTIVE_SSL', 'is_resolving' => 'false' }, :indeterminate],
      'nil data' => [nil, :indeterminate],
      'Array data' => [[{ 'status' => 'ACTIVE_SSL', 'is_resolving' => false }], :indeterminate],
      'String data' => ['ACTIVE_SSL', :indeterminate],
    }.each do |label, (data, expected)|
      it "is #{expected.inspect} for #{label}" do
        expect(chore.classify_live_vhost(data)).to eq(expected)
      end
    end
  end

  describe 'live vhost check' do
    shared_examples 'a live vhost that is not deleted' do |verdict, status|
      it 'returns nil' do
        expect(chore.call(domain)).to be_nil
      end

      it 'asks Approximated once and does not DELETE' do
        chore.call(domain)

        expect(client).to have_received(:get_vhost_by_incoming_address).with(api_key, display_domain).once
        expect(client).not_to have_received(:delete_vhost)
      end

      it 'logs the verdict and remote status at info' do
        chore.call(domain)

        expect(log_lines).to eq(
          [[:info, 'Skipping: DNS has moved but Approximated does not report the vhost idle',
            {
              chore: chore_name,
              domain: display_domain,
              domain_extid: domain.extid,
              verdict: verdict,
              status: status,
            }]],
        )
      end

      include_examples 'local vhost state kept'
      include_examples 'ownership fields untouched'
    end

    context 'when the vhost is ACTIVE_SSL_PROXIED' do
      let(:live_data) { idle_data.merge('status' => 'ACTIVE_SSL_PROXIED') }

      include_examples 'a live vhost that is not deleted', :serving, 'ACTIVE_SSL_PROXIED'
    end

    context 'when the vhost status is UNKNOWN' do
      let(:live_data) { idle_data.merge('status' => 'UNKNOWN') }

      include_examples 'a live vhost that is not deleted', :indeterminate, 'UNKNOWN'
    end

    context 'when the vhost status is blank' do
      let(:live_data) { idle_data.merge('status' => '') }

      include_examples 'a live vhost that is not deleted', :indeterminate, ''
    end

    context 'when is_resolving is true' do
      let(:live_data) { idle_data.merge('is_resolving' => true) }

      include_examples 'a live vhost that is not deleted', :serving, 'ACTIVE_SSL'
    end

    context 'when is_resolving is nil' do
      let(:live_data) { idle_data.merge('is_resolving' => nil) }

      include_examples 'a live vhost that is not deleted', :indeterminate, 'ACTIVE_SSL'
    end

    context 'when apx_hit is true' do
      let(:live_data) { idle_data.merge('apx_hit' => true) }

      include_examples 'a live vhost that is not deleted', :serving, 'ACTIVE_SSL'
    end

    context 'when data is not a Hash' do
      let(:live_data) { ['unexpected'] }

      include_examples 'a live vhost that is not deleted', :indeterminate, nil
    end

    context 'when the response body has no data key' do
      let(:get_result) { api_response(200, { 'unexpected' => true }) }

      include_examples 'a live vhost that is not deleted', :indeterminate, nil
    end

    context 'when the response body is not a Hash' do
      let(:get_result) { api_response(200, '<html>gateway</html>') }

      include_examples 'a live vhost that is not deleted', :indeterminate, nil
    end

    shared_examples 'a vhost that is already gone' do
      it 'does not DELETE' do
        chore.call(domain)

        expect(client).to have_received(:get_vhost_by_incoming_address).with(api_key, display_domain).once
        expect(client).not_to have_received(:delete_vhost)
      end

      it 'logs the removal as already gone' do
        chore.call(domain)

        expect(log_lines).to eq(
          [[:info, 'Removed orphaned Approximated vhost',
            { chore: chore_name, domain: display_domain, domain_extid: domain.extid, remote: 'already gone' }]],
        )
      end

      include_examples 'local vhost state cleared'
    end

    context 'when GET raises the not-found ResponseError' do
      let(:get_result) { not_found_error }

      include_examples 'a vhost that is already gone'
    end

    context 'when GET returns 404' do
      let(:get_result) { api_response(404, { 'error' => 'not found' }) }

      include_examples 'a vhost that is already gone'
    end

    context 'when GET returns 500' do
      let(:get_result) { api_response(500, nil) }

      include_examples 'a CleanupFailed error', 'vhost status check for secrets.example.com returned 500'
      include_examples 'no DELETE'
    end

    context 'when GET returns 429' do
      let(:get_result) { api_response(429, nil) }

      include_examples 'a CleanupFailed error', /returned 429/
      include_examples 'no DELETE'
    end

    context 'when GET returns a 2xx other than 200' do
      let(:get_result) { api_response(204, nil) }

      include_examples 'a CleanupFailed error', /returned 204/
      include_examples 'no DELETE'
    end

    context 'when GET raises the invalid-key ResponseError' do
      let(:get_result) { response_error('Invalid API key') }

      include_examples 'a CleanupFailed error',
        'vhost status check for secrets.example.com failed: Invalid API key'
      include_examples 'no DELETE'
    end

    [Net::OpenTimeout.new('execution expired'), SocketError.new('getaddrinfo: nodename nor servname provided')]
      .each do |error|
      context "when GET raises #{error.class}" do
        let(:get_result) { error }

        it 'propagates the error unwrapped' do
          expect { chore.call(domain) }.to raise_error(error.class, error.message)
        end

        include_examples 'local vhost state kept'
        include_examples 'no DELETE'
        include_examples 'ownership fields untouched'
      end
    end
  end

  # ------------------------------------------------------------------------
  # Guard 9: DELETE
  # ------------------------------------------------------------------------

  describe 'delete' do
    [200, 204].each do |code|
      context "when DELETE returns #{code}" do
        let(:delete_result) { api_response(code, nil) }

        it 'issues exactly one DELETE with the API key and domain' do
          chore.call(domain)
          expect(client).to have_received(:delete_vhost).with(api_key, display_domain).once
        end

        include_examples 'local vhost state cleared'
      end
    end

    context 'when DELETE raises the not-found ResponseError' do
      let(:delete_result) { not_found_error }

      it 'logs the removal' do
        chore.call(domain)
        expect(logged(:info).map { |line| line[1] }).to eq(['Removed orphaned Approximated vhost'])
      end

      include_examples 'local vhost state cleared'
    end

    context 'when DELETE returns 404' do
      let(:delete_result) { api_response(404, nil) }

      include_examples 'local vhost state cleared'
    end

    context 'when DELETE returns 429' do
      let(:delete_result) { api_response(429, nil) }

      include_examples 'a CleanupFailed error', 'vhost delete for secrets.example.com returned 429'
    end

    context 'when DELETE returns 500' do
      let(:delete_result) { api_response(500, nil) }

      include_examples 'a CleanupFailed error', 'vhost delete for secrets.example.com returned 500'

      it 'logs no removal' do
        call_swallowing_errors
        expect(log_lines).to be_empty
      end
    end

    context 'when DELETE raises the invalid-key ResponseError (401)' do
      let(:delete_result) { response_error('Invalid API key') }

      include_examples 'a CleanupFailed error', 'vhost delete for secrets.example.com failed: Invalid API key'
    end

    [Net::OpenTimeout.new('execution expired'), SocketError.new('getaddrinfo: nodename nor servname provided')]
      .each do |error|
      context "when DELETE raises #{error.class}" do
        let(:delete_result) { error }

        it 'propagates the error unwrapped' do
          expect { chore.call(domain) }.to raise_error(error.class, error.message)
        end

        include_examples 'local vhost state kept'
        include_examples 'ownership fields untouched'
      end
    end
  end

  # ------------------------------------------------------------------------
  # Idempotency
  # ------------------------------------------------------------------------

  describe 'idempotency' do
    it 'is a silent no-op on the second call after a successful removal' do
      expect(chore.call(domain)).to be true

      calls_after_first = {
        get: 1, delete: 1, lookups: 1, logs: log_lines.size, saves: saved_fields.size, sleeps: sleeps.size
      }

      expect(chore.call(domain)).to be_nil

      expect(client).to have_received(:get_vhost_by_incoming_address).exactly(calls_after_first[:get]).times
      expect(client).to have_received(:delete_vhost).exactly(calls_after_first[:delete]).times
      expect(resolver).to have_received(:lookup).exactly(calls_after_first[:lookups]).times
      expect(log_lines.size).to eq(calls_after_first[:logs])
      expect(saved_fields.size).to eq(calls_after_first[:saves])
      expect(sleeps.size).to eq(calls_after_first[:sleeps])
    end

    it 'retries the whole sequence after a failed delete' do
      responses = [api_response(500, nil), api_response(200, nil)]
      allow(client).to receive(:delete_vhost) { |*_args| responses.shift }

      expect { chore.call(domain) }.to raise_error(described_class::CleanupFailed)
      expect(domain.vhost).to eq(vhost)

      expect(chore.call(domain)).to be true
      expect(domain.vhost).to be_nil
      expect(client).to have_received(:delete_vhost).twice
    end
  end

  # ------------------------------------------------------------------------
  # Pacing
  # ------------------------------------------------------------------------

  describe 'pacing' do
    it 'sleeps once after the GET and once after the DELETE' do
      chore.call(domain)
      expect(sleeps).to eq([0.5, 0.5])
    end

    it 'uses the configured pause' do
      described_class.new(
        client: client,
        resolver: resolver,
        features: features,
        config: config,
        apply: true,
        pause: 2,
        sleeper: sleeper,
      ).call(domain)

      expect(sleeps).to eq([2, 2])
    end

    it 'defaults the pause to API_PAUSE' do
      described_class.new(
        client: client, resolver: resolver, features: features, config: config, apply: true, sleeper: sleeper,
      ).call(domain)

      expect(sleeps).to eq([described_class::API_PAUSE, described_class::API_PAUSE])
    end

    context 'when the vhost is already gone' do
      let(:get_result) { not_found_error }

      it 'sleeps once, for the GET' do
        chore.call(domain)
        expect(sleeps).to eq([0.5])
      end
    end

    context 'when the GET fails' do
      let(:get_result) { api_response(500, nil) }

      it 'still sleeps once' do
        call_swallowing_errors
        expect(sleeps).to eq([0.5])
      end
    end

    context 'when the GET raises a transport error' do
      let(:get_result) { Net::OpenTimeout.new('execution expired') }

      it 'still sleeps once' do
        call_swallowing_errors
        expect(sleeps).to eq([0.5])
      end
    end

    context 'when the DELETE fails' do
      let(:delete_result) { SocketError.new('connection reset') }

      it 'sleeps once per API call' do
        call_swallowing_errors
        expect(sleeps).to eq([0.5, 0.5])
      end
    end

    context 'when the live vhost is still serving' do
      let(:live_data) { idle_data.merge('is_resolving' => true) }

      it 'sleeps once, for the GET' do
        chore.call(domain)
        expect(sleeps).to eq([0.5])
      end
    end

    [0, 0.0, nil, -1].each do |value|
      context "with pause: #{value.inspect}" do
        let(:pause) { value }

        it 'makes the API calls without sleeping' do
          expect(chore.call(domain)).to be true
          expect(client).to have_received(:delete_vhost).once
          expect(sleeps).to be_empty
        end
      end
    end

    it 'falls back to Kernel#sleep when no sleeper is injected' do
      allow(Kernel).to receive(:sleep)

      # Kernel.method(:sleep) is captured per call, after the stub above.
      described_class.new(
        client: client, resolver: resolver, features: features, config: config, apply: true, pause: 0.25,
      ).call(domain)

      expect(Kernel).to have_received(:sleep).with(0.25).twice
    end
  end

  # ------------------------------------------------------------------------
  # Secrecy
  # ------------------------------------------------------------------------

  describe 'API key secrecy' do
    # One scenario per log line / error message the chore can produce.
    scenarios = {
      'successful delete' => {},
      'already gone' => { get_result: -> { not_found_error } },
      'still serving' => { live_data: -> { idle_data.merge('status' => 'ACTIVE_SSL_PROXIED') } },
      'GET 500' => { get_result: -> { api_response(500, nil) } },
      'GET invalid key' => { get_result: -> { response_error('Invalid API key') } },
      'DELETE 500' => { delete_result: -> { api_response(500, nil) } },
      'DELETE invalid key' => { delete_result: -> { response_error('Invalid API key') } },
      'dry run' => { apply: -> { false } },
      'renamed domain' => { stored_vhost: -> { { 'incoming_address' => 'old-name.example.com' } } },
      'DNS still on cluster' => { dns_answers: -> { { display_domain => snapshot([cluster_ip]) } } },
      'strategy still approximated' => { strategy: -> { 'approximated' } },
    }

    scenarios.each do |label, overrides|
      context "when #{label}" do
        overrides.each { |name, value| let(name) { instance_exec(&value) } }

        it 'keeps the key out of every log line and error message' do
          outcome = call_swallowing_errors
          output  = log_lines.inspect
          output += outcome.message if outcome.is_a?(StandardError)

          expect(output).not_to be_empty
          expect(output).to include(display_domain)
          expect(output).not_to include(api_key)
        end
      end
    end

    it 'does pass the key to the client (the examples above are not vacuous)' do
      chore.call(domain)
      expect(client).to have_received(:delete_vhost).with(api_key, anything)
    end
  end

  # ------------------------------------------------------------------------
  # Sweep through HousekeepingJob
  # ------------------------------------------------------------------------

  describe 'HousekeepingJob sweep' do
    let(:job) { Onetime::Jobs::Scheduled::HousekeepingJob }

    let(:names) do
      {
        idle_first: 'first.sweep.example.com',
        delete_fails: 'broken.sweep.example.com',
        idle_after_failure: 'after.sweep.example.com',
        still_on_cluster: 'pointed.sweep.example.com',
        no_state: 'clean.sweep.example.com',
      }
    end

    let(:records) do
      names.to_h do |key, name|
        state = key == :no_state ? nil : JSON.generate('incoming_address' => name)
        [key, build_domain(name, state)]
      end
    end

    let(:dns_answers) do
      names.to_h { |key, name| [name, snapshot([key == :still_on_cluster ? cluster_ip : elsewhere_ip])] }
    end

    let(:instances) { instance_double(Onetime::CustomDomain.instances.class) }

    # The registered instance talks to the real API and resolver, so the sweep
    # runs with the injected one in its place. Swapped in a before/after pair
    # because the doubles do not exist outside the example lifecycle.
    before do
      @registered_chore                        = Onetime::CustomDomain.chores[chore_name]
      Onetime::CustomDomain.chores[chore_name] = chore
    end

    after do
      Onetime::CustomDomain.chores[chore_name] = @registered_chore
    end

    before do
      # No datastore: the job iterates `instances.each_record`.
      yielder = allow(instances).to receive(:each_record)
      records.each_value { |record| yielder.and_yield(record) }
      allow(Onetime::CustomDomain).to receive(:instances).and_return(instances)

      allow(client).to receive(:get_vhost_by_incoming_address) do |_key, name|
        api_response(200, { 'data' => idle_data.merge('incoming_address' => name) })
      end
      allow(client).to receive(:delete_vhost) do |_key, name|
        api_response(name == names[:delete_fails] ? 500 : 200, nil)
      end
      allow(OT).to receive(:le)
    end

    it 'counts modified and errored records and keeps going after a CleanupFailed' do
      report = job.perform(Onetime::CustomDomain, chore_name)

      expect(report).to eq(
        model: 'Onetime::CustomDomain',
        scanned: 5,
        chores: { chore_name => { modified: 2, errors: 1 } },
      )
    end

    it 'clears only the records whose remote vhost was removed' do
      job.perform('Onetime::CustomDomain', chore_name.to_s)

      expect(records[:idle_first].vhost).to be_nil
      expect(records[:idle_after_failure].vhost).to be_nil
      expect(records[:delete_fails].vhost).to eq(JSON.generate('incoming_address' => names[:delete_fails]))
      expect(records[:still_on_cluster].vhost).to eq(JSON.generate('incoming_address' => names[:still_on_cluster]))
      expect(saved_fields).to eq([[:vhost, :vhost_fetch_failed_at, :updated]] * 2)
    end

    it 'deletes exactly the moved domains, the failing one included' do
      job.perform(Onetime::CustomDomain, chore_name)

      expect(client).to have_received(:delete_vhost).exactly(3).times
      expect(client).not_to have_received(:delete_vhost).with(anything, names[:still_on_cluster])
      expect(client).not_to have_received(:delete_vhost).with(anything, names[:no_state])
    end

    it 'reports the failure through OT.le without the API key' do
      job.perform(Onetime::CustomDomain, chore_name)

      expect(OT).to have_received(:le).once.with(
        a_string_including(records[:delete_fails].identifier, "chore=#{chore_name}", 'returned 500')
          .and(satisfy { |line| !line.include?(api_key) }),
      )
    end

    it 'runs as a dry run sweep when apply is off: nothing modified, nothing called' do
      Onetime::CustomDomain.chores[chore_name] = described_class.new(
        client: client,
        resolver: resolver,
        features: features,
        config: config,
        apply: false,
        pause: pause,
        sleeper: sleeper,
      )

      report = job.perform(Onetime::CustomDomain, chore_name)

      expect(report[:chores][chore_name]).to eq(modified: 0, errors: 0)
      expect(client).not_to have_received(:get_vhost_by_incoming_address)
      expect(client).not_to have_received(:delete_vhost)
      expect(logged(:info).map { |line| line[2][:domain] })
        .to contain_exactly(names[:idle_first], names[:delete_fails], names[:idle_after_failure])
    end
  end
end
