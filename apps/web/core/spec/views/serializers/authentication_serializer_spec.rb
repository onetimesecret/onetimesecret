# apps/web/core/spec/views/serializers/authentication_serializer_spec.rb
#
# frozen_string_literal: true

# Coverage for AuthenticationSerializer.password_auth_permitted? (#3886).
#
# The flag is the POLICY axis of password management, independent of the
# credential-presence axis (has_password): it answers "may this account hold
# a local password?" and is false only when auth mode is not 'full', when the
# app-level restrict_to='sso' mode is active, or when the request's custom
# domain enforces SSO-only. The frontend combines both axes: no password +
# permitted => Set-password affordance; no password + not permitted =>
# SSO-managed empty state.
#
# All collaborators are stubbed — no Redis or SQL required.
#
# Run with:
#   bundle exec rspec apps/web/core/spec/views/serializers/authentication_serializer_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../views/serializers'

RSpec.describe Core::Views::AuthenticationSerializer do
  let(:display_domain) { 'secrets.acme.com' }
  let(:domain_id) { 'cd_test_domain_123' }

  let(:full_auth_config) do
    instance_double(Onetime::AuthConfig, full_enabled?: true, restrict_to: nil)
  end

  before do
    allow(Onetime).to receive(:auth_config).and_return(full_auth_config)
  end

  describe '.password_auth_permitted?' do
    subject(:permitted) { described_class.send(:password_auth_permitted?, view_vars) }

    context 'canonical domain (no display_domain), full auth mode' do
      let(:view_vars) { {} }

      it 'defaults to true for consumer accounts' do
        expect(permitted).to be(true)
      end
    end

    context 'auth mode is not full' do
      let(:view_vars) { {} }
      let(:full_auth_config) do
        instance_double(Onetime::AuthConfig, full_enabled?: false)
      end

      it 'returns false (no password management surface in simple mode)' do
        expect(permitted).to be(false)
      end
    end

    context 'app-level SSO-only mode (restrict_to=sso)' do
      let(:view_vars) { {} }
      let(:full_auth_config) do
        instance_double(Onetime::AuthConfig, full_enabled?: true, restrict_to: 'sso')
      end

      it 'returns false' do
        expect(permitted).to be(false)
      end
    end

    context 'app-level restrict_to=password' do
      let(:view_vars) { {} }
      let(:full_auth_config) do
        instance_double(Onetime::AuthConfig, full_enabled?: true, restrict_to: 'password')
      end

      it 'returns true (only sso restriction forbids passwords)' do
        expect(permitted).to be(true)
      end
    end

    context 'custom domain with tenant SSO' do
      let(:view_vars) { { 'display_domain' => display_domain } }
      let(:custom_domain) { instance_double(Onetime::CustomDomain, identifier: domain_id) }
      let(:sso_config) do
        instance_double(Onetime::CustomDomain::SsoConfig, enforce_sso_only?: enforce)
      end

      before do
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .with(display_domain).and_return(custom_domain)
        allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
          .with(domain_id).and_return(sso_config)
        allow(Onetime::CustomDomain::SsoConfig).to receive(:tenant_sso_available_for?)
          .with(domain_id, sso_config: sso_config).and_return(sso_available)
      end

      context 'SSO configured, available, and ENFORCED' do
        let(:enforce) { true }
        let(:sso_available) { true }

        it 'returns false (per-domain enforcement wins)' do
          expect(permitted).to be(false)
        end
      end

      context 'SSO configured and available but NOT enforced' do
        let(:enforce) { false }
        let(:sso_available) { true }

        it 'returns true (enforcement is the opt-in, per the #3886 decision)' do
          expect(permitted).to be(true)
        end
      end

      context 'SSO config present but unavailable (e.g. disabled)' do
        let(:enforce) { true }
        let(:sso_available) { false }

        it 'returns true (an unavailable config cannot lock accounts to an IdP)' do
          expect(permitted).to be(true)
        end
      end
    end

    context 'custom domain without an SSO config' do
      let(:view_vars) { { 'display_domain' => display_domain } }
      let(:custom_domain) { instance_double(Onetime::CustomDomain, identifier: domain_id) }

      before do
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .with(display_domain).and_return(custom_domain)
        allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
          .with(domain_id).and_return(nil)
      end

      it 'returns true' do
        expect(permitted).to be(true)
      end
    end

    # The resolver reads through the RAISING finder (#4157), so this failure
    # is the one production actually produces — its fail-open sibling
    # load_by_display_domain would have swallowed it into "no tenant config"
    # and quietly advertised the affordance.
    context 'domain resolution raises (e.g. Redis unavailable)' do
      let(:view_vars) { { 'display_domain' => display_domain, 'domain_strategy' => :custom } }

      before do
        allow(OT).to receive(:le)
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .and_raise(Redis::ConnectionError, 'redis down')
      end

      it 'fails closed: an unresolvable domain policy does not advertise the affordance' do
        expect(permitted).to be(false)
      end
    end

    # DomainStrategy publishes display_domain UNCONDITIONALLY (canonical
    # fallback), so a canonical request does reach the lookup — but no
    # per-domain policy can be lost there, and failing it closed would hide
    # the password form from every consumer account during a blip.
    context 'canonical host whose lookup fails' do
      let(:view_vars) do
        { 'display_domain' => 'example.com', 'domain_strategy' => :canonical }
      end

      before do
        allow(OT).to receive(:le)
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .and_raise(Redis::ConnectionError, 'redis down')
      end

      it 'stays permissive: an operator host has no tenant policy to fail closed on' do
        expect(permitted).to be(true)
      end
    end

    context 'canonical domain when storage is down' do
      let(:view_vars) { {} }

      before do
        # Would raise if reached — the empty display_domain early return must
        # keep canonical-domain requests off the fallible lookup path.
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .and_raise(StandardError, 'redis down')
      end

      it 'stays permissive: no tenant policy to resolve, no lookup attempted' do
        expect(permitted).to be(true)
      end
    end
  end

  # The impersonation block is read from the request-scoped context, NOT from
  # the session, so the banner is computed from the same marker that decided
  # which customer the rest of the payload describes.
  describe '.serialize impersonation block' do
    let(:cust) do
      instance_double(Onetime::Customer,
        custid: 'alice@example.com', email: 'alice@example.com',
        created: nil, safe_dump: { 'custid' => 'alice@example.com' })
    end

    let(:view_vars) do
      { 'authenticated' => true, 'cust' => cust, 'sess' => { 'external_id' => 'ur_colonel' } }
    end

    let(:context) do
      {
        'impersonation_id' => 'imp_deadbeefdeadbeef',
        'impersonator_extid' => 'ur_colonel',
        'target_extid' => 'ur_target',
        'target_email' => 'alice@example.com',
        'started_at' => 1_756_700_000,
        'expires_at' => 1_756_701_800,
      }.freeze
    end

    before do
      allow(described_class).to receive(:account_has_password?).and_return(true)
      allow(described_class).to receive(:password_auth_permitted?).and_return(true)
      allow(cust).to receive(:role?).with(:colonel).and_return(false)
      Onetime::SessionImpersonation.clear_context
    end

    after { Onetime::SessionImpersonation.clear_context }

    it 'is nil when nothing is impersonated' do
      expect(described_class.serialize(view_vars)['impersonation']).to be_nil
    end

    it 'emits exactly the six contract fields when active' do
      Fiber[Onetime::SessionImpersonation::FIBER_KEY] = context

      expect(described_class.serialize(view_vars)['impersonation']).to eq(context)
    end

    # `cust` is the TARGET during an impersonation, so gating on the role of
    # the serialized customer would suppress the banner in its only use case.
    it 'emits the block even though the serialized customer is not a colonel' do
      Fiber[Onetime::SessionImpersonation::FIBER_KEY] = context

      expect(described_class.serialize(view_vars)['authenticated']).to be(true)
      expect(described_class.serialize(view_vars)['impersonation']).not_to be_nil
    end
  end

  describe 'identity defense in depth' do
    let(:cust) do
      instance_double(
        Onetime::Customer,
        safe_dump: { 'custid' => 'alice@example.com' },
        custid: 'alice@example.com',
        email: 'alice@example.com',
        created: nil,
      )
    end

    it 'does not let a customer object grant identity when the verdict projection is unauthenticated' do
      output = described_class.serialize(
        'authenticated' => false,
        'awaiting_mfa' => false,
        'cust' => cust,
        'sess' => { 'external_id' => 'ur_alice' },
      )

      expect(output).to include(
        'authenticated' => false,
        'cust' => nil,
        'custid' => nil,
        'email' => nil,
        'customer_since' => nil,
      )
    end

    it 'does not let an authenticated flag grant identity without an evaluated customer' do
      output = described_class.serialize(
        'authenticated' => true,
        'awaiting_mfa' => false,
        'cust' => nil,
        'sess' => { 'external_id' => 'ur_missing' },
      )

      expect(output).to include('authenticated' => false, 'cust' => nil, 'email' => nil)
    end

    it 'exposes no session email or customer data while MFA is pending' do
      output = described_class.serialize(
        'authenticated' => false,
        'awaiting_mfa' => true,
        'session_email' => 'alice@example.com',
        'cust' => nil,
        'sess' => { 'external_id' => 'ur_alice' },
      )

      expect(output).to include(
        'authenticated' => false,
        'awaiting_mfa' => true,
        'cust' => nil,
        'custid' => nil,
        'email' => nil,
      )
    end
  end

  # #4462. `auth_status` is the statement; the two booleans are projections of
  # it. The matrix below is every evaluator status plus both error-recovery
  # rows, fed through the same projection InitializeViewVars uses.
  describe 'auth_status and its compatibility projections' do
    let(:cust) do
      instance_double(
        Onetime::Customer,
        safe_dump: { 'custid' => 'alice@example.com' },
        custid: 'alice@example.com',
        email: 'alice@example.com',
        created: nil,
        role?: false,
      )
    end

    before do
      allow(described_class).to receive_messages(account_has_password?: true, password_auth_permitted?: true)
      Onetime::SessionImpersonation.clear_context
    end

    def verdict(status, reason)
      identity = status == :authenticated ? { principal: cust, customer: cust } : {}
      Onetime::CustomerSessionEvaluator::Verdict.new(status: status, reason: reason, **identity)
    end

    # The view vars InitializeViewVars builds from a verdict.
    def vars_for(verdict)
      {
        'auth_status' => Onetime::SessionAuthStatus.for_verdict(verdict),
        'authenticated' => verdict.authenticated?,
        'awaiting_mfa' => verdict.mfa_pending?,
        'cust' => verdict.customer,
        'sess' => { 'external_id' => 'ur_alice' },
      }
    end

    {
      [:authenticated, :authenticated] => ['authenticated', true, false],
      [:mfa_pending, :awaiting_mfa] => ['mfa_pending', false, true],
      [:anonymous, :session_missing] => ['anonymous', false, false],
      [:anonymous, :not_authenticated] => ['anonymous', false, false],
      [:rejected, :surface_mismatch] => ['anonymous', false, false],
      [:rejected, :active_session_revoked] => ['anonymous', false, false],
      [:rejected, :account_suspended] => ['anonymous', false, false],
      [:unavailable, :active_session_unavailable] => ['unavailable', false, false],
      [:unavailable, :customer_unavailable] => ['unavailable', false, false],
    }.each do |(status, reason), (auth_status, authenticated, awaiting_mfa)|
      it "projects a #{status}/#{reason} verdict as #{auth_status}" do
        output = described_class.serialize(vars_for(verdict(status, reason)))

        expect(output).to include(
          'auth_status' => auth_status,
          'authenticated' => authenticated,
          'awaiting_mfa' => awaiting_mfa,
        )
        expect(output['cust'].nil?).to be(!authenticated)
      end
    end

    it 'covers every evaluator status' do
      expect(Onetime::SessionAuthStatus::BY_VERDICT_STATUS.keys)
        .to match_array(Onetime::CustomerSessionEvaluator::STATUSES)
      expect(Onetime::SessionAuthStatus::BY_VERDICT_STATUS.values.uniq)
        .to match_array(Onetime::SessionAuthStatus::VALUES)
    end

    it 'never puts a rejection reason on the public payload' do
      output = described_class.serialize(vars_for(verdict(:rejected, :surface_mismatch)))

      expect(output.to_json).not_to include('surface_mismatch')
      expect(output).not_to have_key('code')
    end

    describe 'error-recovery render (no strategy result, evaluator not run)' do
      it 'reports unavailable when the raw session names a customer' do
        sess   = { 'external_id' => 'ur_alice' }
        output = described_class.serialize(
          'auth_status' => Onetime::SessionAuthStatus.without_verdict(sess),
          'authenticated' => false, 'awaiting_mfa' => false, 'cust' => nil, 'sess' => sess
        )

        expect(output).to include('auth_status' => 'unavailable', 'authenticated' => false, 'cust' => nil)
        # Deprecated twin, still emitted for a pre-auth_status frontend (#4468).
        expect(output['had_valid_session']).to be(true)
      end

      it 'reports anonymous when it does not' do
        [nil, {}, { 'external_id' => '' }].each do |sess|
          output = described_class.serialize(
            'auth_status' => Onetime::SessionAuthStatus.without_verdict(sess),
            'authenticated' => false, 'awaiting_mfa' => false, 'cust' => nil, 'sess' => sess
          )

          expect(output).to include('auth_status' => 'anonymous', 'authenticated' => false)
        end
      end
    end

    describe 'the projections can never disagree with the status' do
      statuses = Onetime::SessionAuthStatus::VALUES + [nil, 'checking', 'bogus']

      statuses.product([true, false, nil], [true, false, nil], [true, false]).each do |status, authed, mfa, has_cust|
        it "auth_status=#{status.inspect} authenticated=#{authed.inspect} awaiting_mfa=#{mfa.inspect} cust=#{has_cust}" do
          output = described_class.serialize(
            'auth_status' => status, 'authenticated' => authed, 'awaiting_mfa' => mfa,
            'cust' => (has_cust ? cust : nil), 'sess' => {}
          )

          expect(Onetime::SessionAuthStatus::VALUES).to include(output['auth_status'])
          expect(output['authenticated']).to be(output['auth_status'] == 'authenticated')
          expect(output['awaiting_mfa']).to be(output['auth_status'] == 'mfa_pending')
          expect(output['cust'].nil?).to be(output['auth_status'] != 'authenticated')

          # Only withhold: authenticated needs the status (or, for a caller
          # that sent none, the legacy flag), the flag, AND the customer.
          granted = output['auth_status'] == 'authenticated'
          expect(granted).to be(false) unless authed == true && has_cust
          expect(granted).to be(false) if Onetime::SessionAuthStatus::VALUES.include?(status) && status != 'authenticated'
        end
      end
    end

    it 'degrades an authenticated claim without a customer to unavailable, not to an identity' do
      output = described_class.serialize('auth_status' => 'authenticated', 'authenticated' => true, 'cust' => nil)

      expect(output).to include('auth_status' => 'unavailable', 'authenticated' => false, 'cust' => nil)
    end

    it 'derives the status from the legacy booleans for a caller that supplies none' do
      expect(described_class.serialize('authenticated' => true, 'cust' => cust)['auth_status']).to eq('authenticated')
      expect(described_class.serialize('awaiting_mfa' => true)['auth_status']).to eq('mfa_pending')
      expect(described_class.serialize({})['auth_status']).to eq('anonymous')
    end
  end

  describe 'output template' do
    it 'declares auth_status, defaulting to the most restrictive settled state' do
      expect(described_class.output_template).to include(
        'auth_status' => 'anonymous', 'authenticated' => false, 'awaiting_mfa' => false,
      )
    end

    it 'defaults password_auth_permitted to true' do
      expect(described_class.output_template['password_auth_permitted']).to be(true)
    end

    it 'defaults impersonation to nil — absence is the safe state' do
      expect(described_class.output_template).to have_key('impersonation')
      expect(described_class.output_template['impersonation']).to be_nil
    end
  end
end
