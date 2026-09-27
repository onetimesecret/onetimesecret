# spec/unit/onetime/middleware/domain_strategy_custom_domain_stash_spec.rb
#
# frozen_string_literal: true

# Pins the env stashing DomainStrategy performs for :custom classifications
# (#4409): the resolved CustomDomain instance and its stable identifier land
# in env['onetime.custom_domain'] and env['onetime.custom_domain_id'] so
# downstream consumers (surface-bound sessions, tenant SSO hooks) never
# repeat the display_domain lookup and always agree on the tenant id.

require 'spec_helper'
require 'onetime/middleware/domain_strategy'

RSpec.describe Onetime::Middleware::DomainStrategy do
  describe 'env stash for :custom classifications' do
    let(:downstream) { ->(env) { [200, { 'content-type' => 'text/plain' }, ['ok']] } }
    let(:middleware) { described_class.new(downstream) }
    let(:custom_domain) { instance_double(Onetime::CustomDomain, identifier: 'domain-abc-123') }

    before do
      # Feature-flag the domains subsystem on; the class-level state is loaded
      # once from OT.conf during boot, so this stubs the instance-side readers
      # that call through to it. Reading through the middleware instance keeps
      # `#call` on its normal code path.
      allow(middleware).to receive_messages(
        domains_enabled?: true,
        detect_domain_override: [nil, nil],
        canonical_domain: 'example.com',
        canonical_domains_parsed: [PublicSuffix.parse('example.com')],
        anchor_domains_parsed: [PublicSuffix.parse('example.com')],
      )
    end

    it 'reuses the CustomDomain loaded during classification' do
      expect(Onetime::CustomDomain).to receive(:from_display_domain)
        .with('secrets.acme.com').once.and_return(custom_domain)

      env = {
        Rack::DetectHost.result_field_name => 'secrets.acme.com',
      }
      middleware.call(env)

      expect(env['onetime.domain_strategy']).to eq(:custom)
      expect(env['onetime.custom_domain']).to be(custom_domain)
      expect(env['onetime.custom_domain_id']).to eq('domain-abc-123')
    end

    it 'contains a datastore failure during classification and fails closed' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with('secrets.acme.com').and_raise(StandardError, 'redis unavailable')

      env = { Rack::DetectHost.result_field_name => 'secrets.acme.com' }
      expect { middleware.call(env) }.not_to raise_error

      expect(env['onetime.domain_strategy']).to eq(:invalid)
      expect(env).not_to have_key('onetime.custom_domain')
      expect(env).not_to have_key('onetime.custom_domain_id')
    end

    it 'does not stash a CustomDomain for non-:custom classifications' do
      env = { Rack::DetectHost.result_field_name => 'example.com' }
      middleware.call(env)

      expect(env['onetime.domain_strategy']).to eq(:canonical)
      expect(env).not_to have_key('onetime.custom_domain')
      expect(env).not_to have_key('onetime.custom_domain_id')
    end
  end

  describe described_class::Chooserator, '.custom_domain_for' do
    it 'delegates to CustomDomain.from_display_domain' do
      instance = instance_double(Onetime::CustomDomain, identifier: 'x')
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('t.example.com').and_return(instance)

      expect(described_class.custom_domain_for('t.example.com')).to be(instance)
    end

    it 'returns nil for an unknown host' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)

      expect(described_class.custom_domain_for('nope.example')).to be_nil
    end
  end
end
