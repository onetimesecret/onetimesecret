# apps/api/domains/spec/logic/incoming_config/i18n_error_keys_spec.rb
#
# frozen_string_literal: true

# Verifies i18n error_key + args propagation across all migrated raise
# sites in the IncomingConfig Logic classes.
#
# Mirrors the contract established by PRs #3207/#3208: logic classes raise
# with `error_key` (and optional `args` for interpolation) so the HTTP-edge
# ErrorResolver can render a localized message per request locale. Legacy
# English messages are preserved as the I18n.t `default:` fallback.
#
# Each test follows the pattern from
# apps/api/invite/spec/logic/invites/accept_invite_spec.rb:
#   expect { logic.raise_concerns }
#     .to raise_error(Onetime::FormError) do |error|
#       expect(error.error_key).to eq('api.domains.errors.<reason>')
#     end
#
# RUN:
#   pnpm run test:rspec apps/api/domains/spec/logic/incoming_config/i18n_error_keys_spec.rb

require 'spec_helper'
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe 'IncomingConfig Logic error_key propagation' do
  # ---------------------------------------------------------------------------
  # Fixtures (mocked — no Redis required)
  # ---------------------------------------------------------------------------

  let(:domain_extid) { 'ext-domain-test' }
  let(:domain_identifier) { 'domain-test-id' }
  let(:org_extid) { 'ext-org-test' }
  let(:org_id) { 'org-test-id' }
  let(:user_extid) { 'ext-user-test' }

  let(:authenticated_customer) do
    instance_double(
      Onetime::Customer,
      custid: 'cust-test',
      objid: 'cust-test',
      extid: user_extid,
      anonymous?: false,
      verified?: true,
      role: 'user',
    )
  end

  let(:anonymous_customer) do
    instance_double(
      Onetime::Customer,
      custid: nil,
      objid: nil,
      extid: nil,
      anonymous?: true,
      verified?: false,
      role: nil,
    )
  end

  let(:custom_domain) do
    instance_double(
      Onetime::CustomDomain,
      identifier: domain_identifier,
      extid: domain_extid,
      display_domain: 'incoming.example.com',
      org_id: org_id,
    )
  end

  let(:organization) do
    instance_double(
      Onetime::Organization,
      objid: org_id,
      extid: org_extid,
      display_name: 'Test Org',
    )
  end

  let(:session) { { 'authenticated' => true, 'csrf' => 'test-csrf' } }

  let(:strategy_result) do
    double(
      'StrategyResult',
      session: session,
      user: authenticated_customer,
      authenticated?: true,
      metadata: {},
    )
  end

  let(:anonymous_strategy_result) do
    double(
      'StrategyResult',
      session: {},
      user: anonymous_customer,
      authenticated?: false,
      metadata: {},
    )
  end

  let(:incoming_enabled_conf) do
    {
      'features' => { 'incoming' => { 'enabled' => true } },
      'site' => { 'secret' => 'test-secret' },
    }
  end

  # ADR-012 Stage 4: membership with entitlements for authorization
  let(:owner_membership) do
    instance_double(
      Onetime::OrganizationMembership,
      active?: true,
      can?: true  # Default: has all entitlements (owner-level)
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:le)
    allow(OT).to receive(:lw)
    allow(OT).to receive(:conf).and_return(incoming_enabled_conf)

    # Default happy-path stubs; individual contexts override as needed.
    allow(Onetime::CustomDomain).to receive(:find_by_extid)
      .with(domain_extid).and_return(custom_domain)
    allow(Onetime::Organization).to receive(:load)
      .with(org_id).and_return(organization)
    allow(organization).to receive(:owner?).with(authenticated_customer).and_return(true)
    allow(organization).to receive(:can?).with('incoming_secrets').and_return(true)
    allow(Onetime::CustomDomain::IncomingConfig).to receive(:find_by_domain_id)
      .with(domain_identifier).and_return(nil)

    # ADR-012 Stage 4: stub membership lookup for owner
    allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
      .with(org_id, 'cust-test')
      .and_return(owner_membership)
  end

  # ===========================================================================
  # Shared raises across all three Logic classes (base.rb + raise_concerns)
  # ===========================================================================

  shared_examples 'a logic class with shared authorization raises' do
    context 'when the request is anonymous' do
      let(:logic) { described_class.new(anonymous_strategy_result, params) }

      it 'raises FormError tagged with authentication_required' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
          expect(error.error_key).to eq('api.errors.authentication_required')
          expect(error.field).to eq(:user_id)
          expect(error.error_type).to eq(:authentication_required)
        end
      end

      it 'preserves the legacy English message as the I18n fallback' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
          expect(error.message).to eq('Authentication required')
        end
      end
    end

    context 'when the domain extid is missing' do
      let(:params_without_extid) { params.merge('extid' => '') }
      let(:logic) { described_class.new(strategy_result, params_without_extid) }

      it 'raises FormError tagged with domain_id_required' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
          expect(error.error_key).to eq('api.domains.errors.domain_id_required')
          expect(error.field).to eq(:domain_id)
        end
      end
    end

    context 'when the incoming feature flag is disabled' do
      let(:logic) { described_class.new(strategy_result, params) }

      before do
        allow(OT).to receive(:conf).and_return(
          'features' => { 'incoming' => { 'enabled' => false } },
          'site' => { 'secret' => 'test-secret' },
        )
      end

      it 'raises FormError tagged with incoming_secrets_disabled' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
          expect(error.error_key).to eq('api.domains.errors.incoming_secrets_disabled')
          expect(error.error_type).to eq(:forbidden)
        end
      end
    end

    context 'when CustomDomain.find_by_extid returns nil' do
      let(:logic) { described_class.new(strategy_result, params) }

      before do
        allow(Onetime::CustomDomain).to receive(:find_by_extid)
          .with(domain_extid).and_return(nil)
      end

      it 'raises RecordNotFound tagged with domain_not_found and the extid in args' do
        expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound) do |error|
          expect(error.error_key).to eq('api.domains.errors.domain_not_found')
          expect(error.args).to eq(extid: domain_extid)
        end
      end
    end

    context 'when Organization.load returns nil' do
      let(:logic) { described_class.new(strategy_result, params) }

      before do
        allow(Onetime::Organization).to receive(:load)
          .with(org_id).and_return(nil)
      end

      it 'raises RecordNotFound tagged with organization_not_found and the domain in args' do
        expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound) do |error|
          expect(error.error_key).to eq('api.domains.errors.organization_not_found')
          expect(error.args).to eq(domain: 'incoming.example.com')
        end
      end
    end

    context 'when the organization lacks the incoming_secrets entitlement' do
      let(:logic) { described_class.new(strategy_result, params) }

      before do
        allow(organization).to receive(:can?).with('incoming_secrets').and_return(false)
      end

      it 'raises FormError tagged with incoming_secrets_entitlement_required' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
          expect(error.error_key).to eq('api.domains.errors.incoming_secrets_entitlement_required')
          expect(error.error_type).to eq(:forbidden)
        end
      end
    end
  end

  # ===========================================================================
  # GetIncomingConfig
  # ===========================================================================

  describe DomainsAPI::Logic::IncomingConfig::GetIncomingConfig do
    let(:params) { { 'extid' => domain_extid } }

    include_examples 'a logic class with shared authorization raises'
  end

  # ===========================================================================
  # DeleteIncomingConfig
  # ===========================================================================

  describe DomainsAPI::Logic::IncomingConfig::DeleteIncomingConfig do
    let(:params) { { 'extid' => domain_extid } }

    include_examples 'a logic class with shared authorization raises'

    context 'when the IncomingConfig record does not exist for the domain' do
      let(:logic) { described_class.new(strategy_result, params) }

      it 'raises RecordNotFound tagged with incoming_config_not_found and the extid in args' do
        expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound) do |error|
          expect(error.error_key).to eq('api.domains.errors.incoming_config_not_found')
          expect(error.args).to eq(extid: domain_extid)
        end
      end
    end
  end

  # ===========================================================================
  # PutIncomingConfig — extends the shared raises with recipient validation
  # ===========================================================================

  describe DomainsAPI::Logic::IncomingConfig::PutIncomingConfig do
    let(:params) do
      { 'extid' => domain_extid, 'enabled' => true, 'recipients' => [] }
    end

    include_examples 'a logic class with shared authorization raises'

    context 'when recipients exceed MAX_RECIPIENTS' do
      let(:max) { Onetime::CustomDomain::IncomingConfig::MAX_RECIPIENTS }
      let(:too_many) do
        (max + 1).times.map { |i| { 'email' => "r#{i}@example.com", 'name' => "R#{i}" } }
      end
      let(:logic) do
        described_class.new(
          strategy_result,
          params.merge('recipients' => too_many),
        )
      end

      it 'raises FormError tagged with recipients_max_exceeded and the max in args' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
          expect(error.error_key).to eq('api.domains.errors.recipients_max_exceeded')
          expect(error.args).to eq(max: max)
          expect(error.field).to eq(:recipients)
        end
      end
    end

    context 'when a recipient email fails validation' do
      let(:logic) do
        described_class.new(
          strategy_result,
          params.merge('recipients' => [{ 'email' => 'not-an-email', 'name' => 'X' }]),
        )
      end

      before do
        # parse_recipients downcases + strips, so the email reaches the
        # validator as 'not-an-email'. Stub valid_email? to return false
        # for it without touching Truemail's DNS layer.
        allow_any_instance_of(described_class)
          .to receive(:valid_email?).with('not-an-email').and_return(false)
      end

      it 'raises FormError tagged with recipients_invalid_email and the email in args' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
          expect(error.error_key).to eq('api.domains.errors.recipients_invalid_email')
          expect(error.args).to eq(email: 'not-an-email')
          expect(error.field).to eq(:recipients)
        end
      end
    end

    context 'when the recipients list contains duplicate emails' do
      let(:dup_email) { 'dup@example.com' }
      let(:logic) do
        described_class.new(
          strategy_result,
          params.merge('recipients' => [
            { 'email' => dup_email, 'name' => 'First' },
            { 'email' => dup_email, 'name' => 'Second' },
          ]),
        )
      end

      before do
        allow_any_instance_of(described_class)
          .to receive(:valid_email?).with(dup_email).and_return(true)
      end

      it 'raises FormError tagged with recipients_duplicate' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
          expect(error.error_key).to eq('api.domains.errors.recipients_duplicate')
          expect(error.field).to eq(:recipients)
        end
      end
    end
  end

  # ===========================================================================
  # to_h serialization includes error_key for HTTP responses
  # ===========================================================================

  describe 'error.to_h serialization' do
    let(:params) { { 'extid' => '' } }
    let(:logic) { DomainsAPI::Logic::IncomingConfig::GetIncomingConfig.new(strategy_result, params) }

    it 'includes error_key in the serialized error body' do
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
        expect(error.to_h).to include(
          error_key: 'api.domains.errors.domain_id_required',
        )
      end
    end
  end
end
