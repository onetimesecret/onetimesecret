# spec/unit/onetime/models/custom_domain/homepage_config_effective_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Availability matrix for HomepageConfig#effectively_enabled? — the single
# source of truth for whether a homepage is interactive for anonymous
# visitors, consumed by the bootstrap DomainSerializer (read path) and the
# homepage-config API responses (effective_enabled field).
#
# A homepage pointed at the incoming form must fail CLOSED (false → trust
# card) whenever incoming cannot actually receive secrets — feature flag
# off, site.secret missing, config missing/unready, or entitlement lapsed.
# It must never fall open to the create form the operator did not select.
RSpec.describe Onetime::CustomDomain::HomepageConfig do
  let(:organization) { instance_double(Onetime::Organization, can?: true) }
  let(:custom_domain) do
    instance_double(Onetime::CustomDomain, primary_organization: organization)
  end
  let(:incoming_config) do
    instance_double(Onetime::CustomDomain::IncomingConfig, ready?: true)
  end

  let(:conf) do
    {
      'features' => { 'incoming' => { 'enabled' => true } },
      'site' => { 'secret' => 'test-site-secret' },
    }
  end

  subject(:config) do
    described_class.new(domain_id: 'domain123', enabled: 'true', secrets_mode: secrets_mode)
  end

  before do
    allow(OT).to receive(:conf).and_return(conf)
    allow(Onetime::CustomDomain::IncomingConfig).to receive(:find_by_domain_id)
      .with('domain123')
      .and_return(incoming_config)
  end

  describe '#effectively_enabled?' do
    context 'when secrets_mode is create' do
      let(:secrets_mode) { 'create' }

      it 'passes enabled through and never consults IncomingConfig' do
        expect(Onetime::CustomDomain::IncomingConfig).not_to receive(:find_by_domain_id)

        expect(config.effectively_enabled?(custom_domain: custom_domain)).to be(true)
      end

      it 'is false when the homepage is disabled' do
        config.enabled = 'false'
        expect(config.effectively_enabled?(custom_domain: custom_domain)).to be(false)
      end
    end

    context 'when secrets_mode is incoming' do
      let(:secrets_mode) { 'incoming' }

      it 'is true while flag on, site secret present, config ready, and org entitled' do
        expect(config.effectively_enabled?(custom_domain: custom_domain)).to be(true)
      end

      it 'is false when the homepage is disabled, without consulting availability' do
        config.enabled = 'false'
        expect(Onetime::CustomDomain::IncomingConfig).not_to receive(:find_by_domain_id)

        expect(config.effectively_enabled?(custom_domain: custom_domain)).to be(false)
      end

      it 'fails closed when the instance feature flag is off' do
        conf['features']['incoming']['enabled'] = false
        expect(config.effectively_enabled?(custom_domain: custom_domain)).to be(false)
      end

      it 'fails closed when site.secret is missing (hashes cannot be computed)' do
        conf['site'].delete('secret')
        expect(config.effectively_enabled?(custom_domain: custom_domain)).to be(false)
      end

      it 'fails closed when site.secret is present but a blank/whitespace string' do
        conf['site']['secret'] = '   '
        expect(config.effectively_enabled?(custom_domain: custom_domain)).to be(false)
      end

      it 'fails closed when the IncomingConfig is missing' do
        allow(Onetime::CustomDomain::IncomingConfig).to receive(:find_by_domain_id)
          .with('domain123')
          .and_return(nil)

        expect(config.effectively_enabled?(custom_domain: custom_domain)).to be(false)
      end

      it 'fails closed when the IncomingConfig is unready' do
        allow(incoming_config).to receive(:ready?).and_return(false)
        expect(config.effectively_enabled?(custom_domain: custom_domain)).to be(false)
      end

      it 'fails closed when the owning org lost the entitlement' do
        allow(organization).to receive(:can?).with('incoming_secrets').and_return(false)
        expect(config.effectively_enabled?(custom_domain: custom_domain)).to be(false)
      end

      it 'fails closed when no owning org can be resolved' do
        allow(custom_domain).to receive(:primary_organization).and_return(nil)
        expect(config.effectively_enabled?(custom_domain: custom_domain)).to be(false)
      end

      it 'loads the domain itself when none is passed in' do
        loaded_domain = instance_double(
          Onetime::CustomDomain, primary_organization: organization
        )
        allow(config).to receive(:custom_domain).and_return(loaded_domain)

        expect(config.effectively_enabled?).to be(true)
      end
    end

    context 'when secrets_mode is an unrecognized stored value' do
      let(:secrets_mode) { 'corrupted-mode' }

      it 'fails closed rather than falling open to the create form' do
        # Only reachable via direct Redis corruption or a botched migration —
        # the PUT API rejects unknown modes and upsert/create! coerce them. An
        # enabled homepage whose stored mode we cannot interpret must show the
        # non-interactive trust card, not the public create form the operator
        # never selected.
        expect(config.effectively_enabled?(custom_domain: custom_domain)).to be(false)
      end
    end

    context 'when secrets_mode is blank (legacy/unset record)' do
      let(:secrets_mode) { '' }

      it 'reads as the historical create form (interactive)' do
        expect(config.effectively_enabled?(custom_domain: custom_domain)).to be(true)
      end
    end
  end
end
