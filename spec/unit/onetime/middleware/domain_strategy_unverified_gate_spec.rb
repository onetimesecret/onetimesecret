# spec/unit/onetime/middleware/domain_strategy_unverified_gate_spec.rb
#
# frozen_string_literal: true

# A registered custom domain is served (classified :custom) only when
# CustomDomain#served_as_tenant? is true. Any other registered host
# classifies :unverified, and DomainStrategy#call answers it with a 404
# without calling the application below it.
#
# The records here are real, unsaved CustomDomain instances; only the
# display-domain read (CustomDomain.from_display_domain) and the
# features.domains configuration are stubbed, so the predicate and the
# strategy decision run as they do in a request.

require 'spec_helper'
require 'onetime/middleware/domain_strategy'

RSpec.describe Onetime::Middleware::DomainStrategy, 'unverified custom domains' do
  let(:host) { 'secrets.acme.com' }
  let(:chooser) { described_class::Chooserator }
  let(:canonical) { [PublicSuffix.parse('example.com')] }
  let(:app_calls) { [] }
  let(:downstream) do
    lambda do |env|
      app_calls << env
      [200, { 'content-type' => 'text/plain' }, ['tenant page']]
    end
  end
  # Model code logs through the 'App' category too (OT.ld from
  # CustomDomain#init), so this accepts every message and the examples
  # check only the serve_unverified warning.
  let(:app_logger) { instance_double(SemanticLogger::Logger).as_null_object }

  # @param overrides [Hash] features.domains keys to set on a copy of OT.conf
  def configure_domains(**overrides)
    conf    = YAML.load(YAML.dump(OT.conf))
    domains = ((conf['features'] ||= {})['domains'] ||= {})
    overrides.each { |key, value| domains[key.to_s] = value }
    allow(OT).to receive(:conf).and_return(conf)
  end

  def domain_record(org_id: 'org-1', ownership_verified: nil, verified_by_override: nil, legacy_verified: nil)
    record                      = Onetime::CustomDomain.new(display_domain: host, org_id: org_id)
    record.ownership_verified   = ownership_verified unless ownership_verified.nil?
    record.verified_by_override = verified_by_override unless verified_by_override.nil?
    # Hydration of a record written before ownership_verified existed: only
    # the legacy `verified` value is loaded.
    record.instance_variable_set(:@verified, legacy_verified) unless legacy_verified.nil?
    record
  end

  def serve(record)
    allow(Onetime::CustomDomain).to receive(:from_display_domain).with(host).and_return(record)
  end

  def classify(request_host = host)
    chooser.classify(request_host, canonical, anchor_domains: canonical)
  end

  def classify!(request_host = host)
    chooser.classify!(request_host, canonical, anchor_domains: canonical)
  end

  def middleware
    described_class.new(downstream).tap do |instance|
      allow(instance).to receive_messages(
        domains_enabled?: true,
        canonical_domain: 'example.com',
        canonical_domains_parsed: canonical,
        anchor_domains_parsed: canonical,
      )
    end
  end

  def request(request_host = host)
    env                                     = { Rack::DetectHost.result_field_name => request_host }
    status, headers, body                   = middleware.call(env)
    [status, headers, body.to_enum.to_a.join, env]
  end

  before do
    Onetime::CustomDomain.reset_serving_policy!
    allow(Onetime).to receive(:get_logger).and_call_original
    allow(Onetime).to receive(:get_logger).with('App').and_return(app_logger)
  end

  after { Onetime::CustomDomain.reset_serving_policy! }

  context 'under a strategy that proves ownership (approximated)' do
    before { configure_domains(validation_strategy: 'approximated') }

    it 'classifies a found record whose ownership is not verified :unverified' do
      serve(domain_record)

      classification = classify
      expect(classification.strategy).to eq(:unverified)
      expect(classification.custom_domain).to be_nil
      expect(classify!.strategy).to eq(:unverified)
      expect(chooser.choose_strategy(host, canonical, anchor_domains: canonical)).to eq(:unverified)
    end

    it 'treats an explicit false the same as unset' do
      serve(domain_record(ownership_verified: false))

      expect(classify.strategy).to eq(:unverified)
    end

    it 'answers 404 with a fixed body and no-store, without calling the application' do
      serve(domain_record)

      status, headers, body, env = request

      expect(status).to eq(404)
      expect(body).to eq('This domain is not configured')
      expect(headers['cache-control']).to eq('no-store')
      expect(headers['content-type']).to eq('text/plain; charset=utf-8')
      expect(headers['content-length']).to eq(body.bytesize.to_s)
      expect(app_calls).to be_empty

      # Nothing names the registration: no classification header, and no
      # onetime.* key in env for anything upstream to read.
      expect(headers.keys.map(&:downcase)).not_to include('o-domain-strategy', 'o-display-domain')
      expect(env.keys.grep(/\Aonetime\./)).to be_empty
    end

    it 'gives every path and method on the host the same answer' do
      serve(domain_record)

      ['/', '/signin', '/auth/sso/oidc', '/api/v2/incoming/config'].each do |path|
        %w[GET POST].each do |method|
          env = {
            Rack::DetectHost.result_field_name => host,
            'PATH_INFO' => path,
            'REQUEST_METHOD' => method,
          }
          status, _headers, body = middleware.call(env)

          expect([status, body.to_enum.to_a.join]).to eq([404, 'This domain is not configured']),
            "#{method} #{path}"
        end
      end
      expect(app_calls).to be_empty
    end

    it 'serves a domain whose ownership is verified' do
      record = domain_record(ownership_verified: true)
      serve(record)

      expect(classify.strategy).to eq(:custom)
      expect(classify.custom_domain).to be(record)

      status, headers, body, env = request
      expect([status, body]).to eq([200, 'tenant page'])
      expect(headers['O-Domain-Strategy']).to eq('custom')
      expect(env['onetime.custom_domain']).to be(record)
      expect(app_calls.size).to eq(1)
    end

    it 'serves a domain held verified by a colonel override' do
      serve(domain_record(ownership_verified: true, verified_by_override: true))

      expect(classify.strategy).to eq(:custom)
      expect(classify!.strategy).to eq(:custom)
    end

    it 'serves a record whose only ownership value is the legacy verified flag' do
      serve(domain_record(legacy_verified: true))

      expect(classify.strategy).to eq(:custom)
    end

    it 'does not serve an orphan (no organization), verified or not' do
      serve(domain_record(org_id: nil, ownership_verified: true))

      expect(classify.strategy).to eq(:unverified)
      expect(request.first).to eq(404)
    end
  end

  # The 404 is answered before the request logger, so DomainStrategy logs
  # the answer itself: one info line with the host and why it is not served,
  # and nothing from the record.
  describe 'logging an :unverified answer' do
    let(:http_logger) { instance_double(SemanticLogger::Logger).as_null_object }
    let(:message) { '[DomainStrategy] custom domain not served' }

    before do
      configure_domains(validation_strategy: 'approximated')
      allow(Onetime).to receive(:get_logger).with('HTTP').and_return(http_logger)
    end

    it 'logs one info line with the host and the reason unverified' do
      serve(domain_record)

      request

      expect(http_logger).to have_received(:info).with(message, { host: host, reason: :unverified }).once
    end

    it 'gives the reason orphan for a record with no organization' do
      serve(domain_record(org_id: nil, ownership_verified: true))

      request

      expect(http_logger).to have_received(:info).with(message, { host: host, reason: :orphan }).once
    end

    it 'logs no such line for a served host' do
      serve(domain_record(ownership_verified: true))

      request

      expect(http_logger).not_to have_received(:info).with(message, anything)
    end
  end

  describe Onetime::CustomDomain, '#unserved_reason' do
    it 'answers nil for a served record, :orphan without an organization, :unverified otherwise' do
      configure_domains(validation_strategy: 'approximated')

      expect(domain_record(ownership_verified: true).unserved_reason).to be_nil
      expect(domain_record(org_id: '', ownership_verified: true).unserved_reason).to eq(:orphan)
      expect(domain_record.unserved_reason).to eq(:unverified)
    end
  end

  context 'under caddy_on_demand' do
    before { configure_domains(validation_strategy: 'caddy_on_demand') }

    it 'classifies an unverified record :unverified and a verified one :custom' do
      serve(domain_record)
      expect(classify.strategy).to eq(:unverified)

      serve(domain_record(ownership_verified: true))
      expect(classify.strategy).to eq(:custom)
    end
  end

  # ADR-049: under a strategy that does not prove ownership, registration by
  # the owning organization is the basis.
  context 'under passthrough' do
    before { configure_domains(validation_strategy: 'passthrough') }

    it 'serves an owned record that was never verified' do
      serve(domain_record)

      expect(classify.strategy).to eq(:custom)
      expect(request.first).to eq(200)
    end

    it 'still does not serve an orphan' do
      serve(domain_record(org_id: ''))

      expect(classify.strategy).to eq(:unverified)
      expect(classify!.strategy).to eq(:unverified)
      expect(request.first).to eq(404)
      expect(app_calls).to be_empty
    end
  end

  context 'when the strategy configuration changes between requests' do
    it 'decides again from the configuration in effect, with no reset' do
      serve(domain_record)

      configure_domains(validation_strategy: 'approximated')
      expect(classify.strategy).to eq(:unverified)

      configure_domains(validation_strategy: 'passthrough')
      expect(classify.strategy).to eq(:custom)

      configure_domains(validation_strategy: 'caddy')
      expect(classify.strategy).to eq(:unverified)
    end
  end

  context 'with an unknown strategy under strict_strategy' do
    before do
      configure_domains(validation_strategy: 'no-such-strategy', strict_strategy: true)
      allow(OT).to receive(:le)
    end

    it 'fails closed: ownership proof is required' do
      serve(domain_record)

      expect(classify.strategy).to eq(:unverified)
    end
  end

  context 'when the custom-domain read fails' do
    let(:http_logger) { instance_double(SemanticLogger::Logger, error: nil, debug: nil) }

    before do
      configure_domains(validation_strategy: 'approximated')
      allow(Onetime).to receive(:http_logger).and_return(http_logger)
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with(host).and_raise(Redis::BaseError, 'connection reset')
    end

    it 'classifies nil (→ :invalid), never :unverified' do
      expect(classify.strategy).to be_nil
      expect { classify! }.to raise_error(Redis::BaseError)

      status, headers, _body, env = request
      expect(status).to eq(200)
      expect(env['onetime.domain_strategy']).to eq(:invalid)
      expect(headers['O-Domain-Strategy']).to eq('invalid')
    end
  end

  describe 'features.domains.serve_unverified' do
    # The setting's warning is logged at boot (ConfigureDomains), not when a
    # request is served.
    it 'serves an unverified record as :custom when true, without logging a warning' do
      configure_domains(validation_strategy: 'approximated', serve_unverified: true)
      record = domain_record
      serve(record)

      expect(classify.strategy).to eq(:custom)
      expect(classify!.strategy).to eq(:custom)
      status, _headers, _body, env = request
      expect(status).to eq(200)
      expect(env['onetime.custom_domain']).to be(record)

      expect(app_logger).not_to have_received(:warn).with('custom_domain.serve_unverified_enabled', anything)
    end

    it 'still does not serve an orphan (no organization), verified or not' do
      configure_domains(validation_strategy: 'approximated', serve_unverified: true)

      [nil, ''].each do |org_id|
        [nil, true].each do |ownership_verified|
          record = domain_record(org_id: org_id, ownership_verified: ownership_verified)
          serve(record)

          expect([record.served_as_tenant?, classify.strategy]).to eq([false, :unverified]),
            "org_id=#{org_id.inspect} ownership_verified=#{ownership_verified.inspect}"
        end
      end
      expect(request.first).to eq(404)
    end

    it 'still does not serve an orphan under passthrough' do
      configure_domains(validation_strategy: 'passthrough', serve_unverified: true)
      serve(domain_record(org_id: nil))

      expect(classify.strategy).to eq(:unverified)
    end

    # Strict boolean: the ERB in config.defaults.yaml yields true or false,
    # and anything else (a string from a hand-written config) enforces.
    ['true', 'yes', 1, nil, false].each do |value|
      it "enforces for #{value.inspect}" do
        configure_domains(validation_strategy: 'approximated', serve_unverified: value)
        serve(domain_record)

        expect(classify.strategy).to eq(:unverified)
        expect(app_logger).not_to have_received(:warn).with('custom_domain.serve_unverified_enabled', anything)
      end
    end
  end

  describe Onetime::CustomDomain, '#serving_authorized?' do
    it 'reads no datastore: it answers for a record that was never saved' do
      configure_domains(validation_strategy: 'approximated')
      allow(Familia).to receive(:dbclient).and_raise('no datastore access expected')

      expect(domain_record(ownership_verified: true).serving_authorized?).to be(true)
      expect(domain_record.serving_authorized?).to be(false)
    end

    it 'ignores serve_unverified, which only served_as_tenant? honours' do
      configure_domains(validation_strategy: 'approximated', serve_unverified: true)

      expect(domain_record.serving_authorized?).to be(false)
      expect(domain_record.served_as_tenant?).to be(true)
    end
  end
end
