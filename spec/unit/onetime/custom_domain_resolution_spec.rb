# spec/unit/onetime/custom_domain_resolution_spec.rb
#
# frozen_string_literal: true

# Onetime::CustomDomainResolution (#4220): the found / absent / read_failed
# value DomainStrategy publishes for the request host, and the accessors the
# request-path consumers read it through. The consumers' own reactions to
# each state are pinned by their own specs; the last group here checks only
# that they read the shared value instead of looking the host up again.

require 'spec_helper'
require 'onetime/middleware/domain_strategy'
require 'onetime/custom_domain_resolution'
require 'onetime/tenant_sso_resolution'
require 'onetime/session/surface'
require_relative '../../../apps/web/auth/signin_gate'
require_relative '../../../apps/web/auth/restrict_to'
require_relative '../../../apps/web/auth/lib/public_host'

RSpec.describe Onetime::CustomDomainResolution do
  let(:record) { instance_double(Onetime::CustomDomain, identifier: 'domain-abc', verified: true) }
  let(:failure) { Redis::BaseError.new('connection reset') }

  describe 'states' do
    it 'found carries the record and its identifier' do
      resolution = described_class.found('secrets.acme.com', record)

      expect([resolution.found?, resolution.absent?, resolution.read_failed?]).to eq([true, false, false])
      expect(resolution.record).to be(record)
      expect(resolution.record!).to be(record)
      expect(resolution.identifier).to eq('domain-abc')
      expect(resolution.host).to eq('secrets.acme.com')
    end

    it 'absent has no record and does not raise' do
      resolution = described_class.absent('nope.example.org')

      expect([resolution.found?, resolution.absent?, resolution.read_failed?]).to eq([false, true, false])
      expect(resolution.record).to be_nil
      expect(resolution.record!).to be_nil
      expect(resolution.identifier).to be_nil
    end

    it 'read_failed keeps the exception, answers nil from #record and raises it from #record!' do
      resolution = described_class.read_failed('secrets.acme.com', failure)

      expect([resolution.found?, resolution.absent?, resolution.read_failed?]).to eq([false, false, true])
      expect(resolution.record).to be_nil
      expect(resolution.error).to be(failure)
      expect { resolution.record! }.to raise_error(failure)
    end

    it 'is frozen' do
      expect(described_class.absent('a.example.org')).to be_frozen
      expect(described_class.found('a.example.org', record).host).to be_frozen
    end

    it 'rejects an unknown state' do
      expect { described_class.new(state: :maybe, host: 'a.example.org') }.to raise_error(ArgumentError)
    end

    it 'leaves the authorization slot unset' do
      expect(described_class.found('secrets.acme.com', record).authorization).to be_nil
    end
  end

  describe '.lookup' do
    it 'reads once through CustomDomain.from_display_domain' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('secrets.acme.com').and_return(record)

      expect(described_class.lookup('secrets.acme.com')).to be_found
      expect(Onetime::CustomDomain).to have_received(:from_display_domain).once
    end

    it 'answers absent for a nil record' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)

      expect(described_class.lookup('nope.example.org')).to be_absent
    end

    it 'answers read_failed, not absent, when the read raises' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_raise(failure)

      resolution = described_class.lookup('secrets.acme.com')
      expect(resolution).to be_read_failed
      expect(resolution.error).to be(failure)
    end
  end

  describe '.for' do
    it 'returns the published resolution without reading' do
      published = described_class.found('secrets.acme.com', record)
      env       = { 'onetime.display_domain' => 'secrets.acme.com', described_class::ENV_KEY => published }
      allow(Onetime::CustomDomain).to receive(:from_display_domain)

      expect(described_class.for(env)).to be(published)
      expect(Onetime::CustomDomain).not_to have_received(:from_display_domain)
    end

    it 'reads once and publishes when nothing was published' do
      env = { 'onetime.display_domain' => 'example.com' }
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('example.com').and_return(nil)

      first = described_class.for(env)
      expect(first).to be_absent
      expect(described_class.for(env)).to be(first)
      expect(Onetime::CustomDomain).to have_received(:from_display_domain).once
    end

    it 'does not read again after a failed read' do
      env = { 'onetime.display_domain' => 'secrets.acme.com' }
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_raise(failure)

      expect(described_class.for(env)).to be_read_failed
      expect(described_class.for(env)).to be_read_failed
      expect(Onetime::CustomDomain).to have_received(:from_display_domain).once
    end

    it 'ignores a published resolution for a different host' do
      env = {
        'onetime.display_domain' => 'example.com',
        described_class::ENV_KEY => described_class.found('secrets.acme.com', record),
      }
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('example.com').and_return(nil)

      expect(described_class.for(env)).to be_absent
    end

    it 'reads without publishing when there is no env' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)

      expect(described_class.for(nil)).to be_absent
    end
  end

  describe '.for_host' do
    let(:published) { described_class.found('secrets.acme.com', record) }
    let(:env) { { 'onetime.display_domain' => 'secrets.acme.com', described_class::ENV_KEY => published } }

    it 'uses the request resolution when the host is the display domain' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)

      expect(described_class.for_host(env, 'Secrets.Acme.com')).to be(published)
      expect(Onetime::CustomDomain).not_to have_received(:from_display_domain)
    end

    it 'reads a different host directly and leaves the published value alone' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('other.example.org').and_return(nil)

      expect(described_class.for_host(env, 'other.example.org')).to be_absent
      expect(env[described_class::ENV_KEY]).to be(published)
    end
  end

  describe 'what DomainStrategy publishes' do
    let(:downstream) { ->(_env) { [200, { 'content-type' => 'text/plain' }, ['ok']] } }
    let(:middleware) { Onetime::Middleware::DomainStrategy.new(downstream) }

    before do
      allow(middleware).to receive_messages(
        domains_enabled?: true,
        detect_domain_override: [nil, nil],
        canonical_domain: 'example.com',
        canonical_domains_parsed: [PublicSuffix.parse('example.com')],
        anchor_domains_parsed: [PublicSuffix.parse('example.com')],
      )
    end

    def call_for(host)
      env = { Rack::DetectHost.result_field_name => host }
      middleware.call(env)
      env
    end

    it 'publishes found for a registered custom domain, from one read' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('secrets.acme.com').and_return(record)

      env        = call_for('secrets.acme.com')
      resolution = env[described_class::ENV_KEY]

      expect(env['onetime.domain_strategy']).to eq(:custom)
      expect(resolution).to be_found
      expect(resolution.record).to be(env['onetime.custom_domain'])
      expect(resolution.host).to eq(env['onetime.display_domain'])
      expect(Onetime::CustomDomain).to have_received(:from_display_domain).once
    end

    it 'publishes absent for an unregistered host' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)

      env = call_for('elsewhere.org')

      expect(env['onetime.domain_strategy']).to eq(:invalid)
      expect(env[described_class::ENV_KEY]).to be_absent
    end

    it 'publishes absent for a platform subdomain' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)

      env = call_for('eu.example.com')

      expect(env['onetime.domain_strategy']).to eq(:subdomain)
      expect(env[described_class::ENV_KEY]).to be_absent
    end

    it 'publishes read_failed, and still classifies :invalid, when the read raises' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_raise(failure)

      env        = call_for('secrets.acme.com')
      resolution = env[described_class::ENV_KEY]

      expect(env['onetime.domain_strategy']).to eq(:invalid)
      expect(resolution).to be_read_failed
      expect(resolution.error).to be(failure)
      expect(env).not_to have_key('onetime.custom_domain')
    end

    it 'publishes nothing for the canonical host, which needs no read' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)

      env = call_for('example.com')

      expect(env['onetime.domain_strategy']).to eq(:canonical)
      expect(env).not_to have_key(described_class::ENV_KEY)
      expect(Onetime::CustomDomain).not_to have_received(:from_display_domain)
    end

    it 'publishes nothing when domains are disabled' do
      allow(middleware).to receive(:domains_enabled?).and_return(false)
      allow(Onetime::CustomDomain).to receive(:from_display_domain)

      env = call_for('secrets.acme.com')

      expect(env).not_to have_key(described_class::ENV_KEY)
      expect(Onetime::CustomDomain).not_to have_received(:from_display_domain)
    end

    it 'clears a value left in the env by an earlier pass' do
      env = {
        Rack::DetectHost.result_field_name => 'example.com',
        described_class::ENV_KEY => described_class.found('secrets.acme.com', record),
      }
      middleware.call(env)

      expect(env).not_to have_key(described_class::ENV_KEY)
    end
  end

  describe 'Chooserator' do
    let(:chooser) { Onetime::Middleware::DomainStrategy::Chooserator }

    before { allow(Onetime).to receive(:http_logger).and_return(instance_double(SemanticLogger::Logger, error: nil, debug: nil)) }

    it 'classify returns the read_failed resolution with a nil strategy' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_raise(failure)

      classification = chooser.classify('secrets.acme.com', 'example.com')

      expect(classification.strategy).to be_nil
      expect(classification.custom_domain).to be_nil
      expect(classification.resolution).to be_read_failed
    end

    it 'classify! raises the read failure' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_raise(failure)

      expect { chooser.classify!('secrets.acme.com', 'example.com') }.to raise_error(failure)
    end

    it 'carries no resolution for an exact canonical match' do
      expect(chooser.classify('example.com', 'example.com').resolution).to be_nil
    end
  end

  # One read per request: after the middleware resolved the host, the
  # consumers below answer from the published value and never call the
  # loader. The loader is stubbed to raise so a second read would show.
  describe 'consumers read the published resolution' do
    let(:published) { described_class.found('secrets.acme.com', record) }
    let(:env) do
      {
        'onetime.display_domain' => 'secrets.acme.com',
        'onetime.domain_strategy' => :custom,
        'onetime.custom_domain' => record,
        'onetime.custom_domain_id' => 'domain-abc',
        described_class::ENV_KEY => published,
      }
    end

    before do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_raise(failure)
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_raise(failure)
      allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_host?).and_return(false)
    end

    it 'TenantSsoResolution.for' do
      resolution = Onetime::TenantSsoResolution.for(env)

      expect(resolution.domain_id).to eq('domain-abc')
      expect(resolution.custom_domain).to be(record)
      expect(resolution.domain_read_failed?).to be(false)
    end

    it 'TenantSsoResolution.for answers its failure sentinel for a published read_failed' do
      env[described_class::ENV_KEY]  = described_class.read_failed('secrets.acme.com', failure)
      env['onetime.domain_strategy'] = :invalid

      expect(Onetime::TenantSsoResolution.for(env).domain_read_failed?).to be(true)
    end

    it 'Auth::SigninGate and Auth::RestrictTo' do
      expect(Auth::SigninGate.send(:domain_id_for, env)).to eq('domain-abc')
      expect(Auth::RestrictTo.send(:domain_id_for, env)).to eq('domain-abc')
    end

    it 'Auth::SigninGate and Auth::RestrictTo raise a published read failure' do
      env[described_class::ENV_KEY] = described_class.read_failed('secrets.acme.com', failure)

      expect { Auth::SigninGate.send(:domain_id_for, env) }.to raise_error(failure)
      expect { Auth::RestrictTo.send(:domain_id_for, env) }.to raise_error(failure)
    end

    it 'Auth::PublicHost.resolve' do
      expect(Auth::PublicHost.resolve(env)).to eq('secrets.acme.com')
    end

    it 'Auth::PublicHost.resolve answers nil for a published read_failed' do
      env[described_class::ENV_KEY] = described_class.read_failed('secrets.acme.com', failure)

      expect(Auth::PublicHost.resolve(env)).to be_nil
    end

    it 'SessionSurface answers :unavailable for a published read_failed without reading' do
      env[described_class::ENV_KEY]  = described_class.read_failed('secrets.acme.com', failure)
      env['onetime.domain_strategy'] = :invalid
      allow(Onetime).to receive(:http_logger).and_return(instance_double(SemanticLogger::Logger, error: nil))
      session                        = { Onetime::SessionSurface::KEY => { 'kind' => 'custom', 'id' => 'domain-abc' } }

      expect(Onetime::SessionSurface.match_status(session, env)).to eq(:unavailable)
      expect(Onetime::CustomDomain).not_to have_received(:from_display_domain)
    end

    it 'SessionSurface answers nil for a published absent without reading' do
      env[described_class::ENV_KEY]  = described_class.absent('secrets.acme.com')
      env['onetime.domain_strategy'] = :invalid

      expect(Onetime::SessionSurface.for_env(env)).to be_nil
      expect(Onetime::CustomDomain).not_to have_received(:from_display_domain)
    end
  end
end
