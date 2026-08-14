# apps/web/auth/spec/unit/signin_gate_spec.rb
#
# frozen_string_literal: true

# Unit tests for the sign-in / sign-up OPT-IN route gate
# (ADR-024#operator-defaults-require-positive-classification,
# ADR-034#reject-as-not-found-not-forbidden, #4163).
#
# WHAT IS UNDER TEST. Two things, and only two:
#
#   1. THE CLASSIFICATION. Every Rodauth route symbol is on exactly one side of
#      this axis — SIGNIN_ROUTES, SIGNUP_ROUTES, or an explicit exemption. A
#      route nobody classified defaults to "allowed", which is the exact defect
#      #4163 closes, so an unclassified route must RED this file rather than
#      quietly pass.
#   2. THE DECISION AND THE HALT. Which resolver the gate asks, with which
#      inputs, and what it does with the answer.
#
# RESOLUTION ITSELF IS NOT UNDER TEST — it is the model's
# (SigninConfig.resolve_signin_enabled_for_request /
# SignupConfig.resolve_signup_enabled_for_request,
# ADR-034#resolution-is-model-owned) and is tested there and in the parity
# spec. So the DATASTORE reads are stubbed and the resolvers run for real: a
# gate that agreed with a stubbed resolver would prove nothing about the host
# it guards.
#
# WHY THIS EXISTS ALONGSIDE THE INTEGRATION SPEC, same reason as its restrict_to
# sibling: the full-mode lane boots with email_auth and webauthn disabled, so
# those endpoints are absent and any example that POSTs to them skips. Here the
# routing decision is exercised directly against @current_route, so every gated
# route symbol is covered whatever features a lane happens to load.
#
# Run:
#   bundle exec rspec apps/web/auth/spec/unit/signin_gate_spec.rb

require_relative '../spec_helper'

# The POLICY module only — deliberately NOT config/hooks/restrict_to.rb, which
# is namespaced into Auth::Config and would drag the whole boot chain in. That
# separation is why apps/web/auth/signin_gate.rb exists beside restrict_to.rb;
# this require is also the assertion that it holds.
require_relative '../../signin_gate'

# The OTHER axis over the same route table. Required for the coverage assertion
# below, which compares the two classifications against each other rather than
# against a transcription — a route added to one and forgotten in the other is
# precisely the drift that leaves a gate looking closed.
require_relative '../../restrict_to'

RSpec.describe Auth::SigninGate do
  let(:display_domain) { 'tenant.example.com' }
  let(:domain_id)      { 'domain_4163' }

  let(:custom_domain) { instance_double(Onetime::CustomDomain, identifier: domain_id) }

  # Install-level: sign-in, sign-up and magic links all ON, so every rejection
  # below is the HOST's answer and not a global kill switch.
  let(:auth_settings)     { { 'enabled' => true, 'signin' => true, 'signup' => true } }
  let(:email_auth_global) { true }

  let(:signin_config) { nil }
  let(:signup_config) { nil }

  let(:mock_auth_config) do
    instance_double(Onetime::AuthConfig, email_auth_enabled?: email_auth_global)
  end

  before do
    allow(Onetime).to receive(:auth_config).and_return(mock_auth_config)
    allow(OT).to receive(:conf).and_return({ 'site' => { 'authentication' => auth_settings } })
    allow(Auth::Logging).to receive(:log_auth_event)

    # from_display_domain, not load_by_display_domain: the gate reads through
    # the NON-swallowing finder on purpose (#4157), and stubbing the wrong one
    # would leave it reading a real (empty) datastore — every example would then
    # pass vacuously against "no tenant config".
    allow(Onetime::CustomDomain).to receive(:from_display_domain)
      .with(display_domain).and_return(custom_domain)
    allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
      .with(domain_id).and_return(signin_config)
    allow(Onetime::CustomDomain::SignupConfig).to receive(:find_by_domain_id)
      .with(domain_id).and_return(signup_config)
  end

  def signin_config_double(signin_enabled: true, email_auth_enabled: true, enabled: true)
    instance_double(
      Onetime::CustomDomain::SigninConfig,
      domain_id: domain_id,
      enabled?: enabled,
      signin_enabled?: signin_enabled,
      email_auth_enabled?: email_auth_enabled,
    )
  end

  def signup_config_double(signup_enabled: true, enabled: true)
    instance_double(
      Onetime::CustomDomain::SignupConfig,
      domain_id: domain_id,
      enabled?: enabled,
      signup_enabled?: signup_enabled,
    )
  end

  # Minimal stand-in for the Rodauth instance the before_rodauth block runs
  # against: current_route, request.env, request.path and the halt.
  # `internal_request?` is private on the real object, which is why the gate
  # reaches it with send — the double mirrors that.
  def rodauth_double(route, strategy: :custom, internal: false)
    request = double(
      'request',
      env: {
        'onetime.display_domain' => display_domain,
        'onetime.domain_strategy' => strategy,
      },
      path: "/#{route}",
    )
    allow(request).to receive(:halt) { |response| throw :halted, response }

    instance = double('rodauth', current_route: route, request: request)
    allow(instance).to receive(:send).with(:internal_request?).and_return(internal)
    instance
  end

  # Runs the gate and returns the halt response, or nil when it allowed through.
  def gate(route, strategy: :custom, internal: false)
    catch(:halted) do
      described_class.enforce_route!(rodauth_double(route, strategy: strategy, internal: internal))
      nil
    end
  end

  def expect_rejected(route, **)
    halted = gate(route, **)

    expect(halted&.first).to eq(404), "#{route} was ALLOWED where the host never opted in"
    expect(JSON.parse(halted[2].first)['error_type']).to eq('NotFound')
  end

  def expect_allowed(route, **)
    expect(gate(route, **)).to be_nil, "#{route} was rejected where the host opted in"
  end

  # ==========================================================================
  # 1. Classification coverage — the guard against a route slipping past
  # ==========================================================================
  #
  # The gate can only be as complete as its tables. The integration spec checks
  # them against the LIVE route_hash, which covers only what a lane mounts;
  # here they are checked against the other axis's tables, which enumerate the
  # same Rodauth route universe and are maintained by the same reviewers.
  #
  describe 'route classification' do
    let(:signin_routes) { described_class::SIGNIN_ROUTES }
    let(:signup_routes) { described_class::SIGNUP_ROUTES }
    let(:exempt)        { described_class::UNGATED_ROUTES }

    it 'classifies every route the restrict_to axis knows about' do
      known        = Auth::RestrictTo::PRE_AUTH_ROUTES.keys + Auth::RestrictTo::UNGATED_ROUTES
      classified   = signin_routes + signup_routes + exempt
      unclassified = known - classified

      expect(unclassified).to be_empty,
        "Rodauth routes with no sign-in/sign-up axis classification: #{unclassified.inspect}\n" \
        'Add each to SIGNIN_ROUTES / SIGNUP_ROUTES (with its function) or UNGATED_ROUTES ' \
        "(with a reason) in apps/web/auth/signin_gate.rb. See ADR-024.\n" \
        'Defaulting to "allowed" is the #4163 defect.'
    end

    it 'invents no route the restrict_to axis has never heard of' do
      known  = Auth::RestrictTo::PRE_AUTH_ROUTES.keys + Auth::RestrictTo::UNGATED_ROUTES
      unique = (signin_routes + signup_routes + exempt) - known

      expect(unique).to be_empty,
        "classified here but unknown to Auth::RestrictTo: #{unique.inspect} — one of the two tables is stale"
    end

    it 'puts every route on exactly ONE side (no double classification)' do
      all = described_class::SIGNIN_ROUTES + described_class::SIGNUP_ROUTES + exempt

      expect(all.tally.select { |_route, count| count > 1 }).to be_empty
    end

    it 'derives axis_for from the two gated tables and nothing else' do
      signin_routes.each { |route| expect(described_class.axis_for(route)).to eq(:signin) }
      signup_routes.each { |route| expect(described_class.axis_for(route)).to eq(:signup) }
      exempt.each        { |route| expect(described_class.axis_for(route)).to be_nil }
    end

    it 'reads a non-trivial table (guards against a vacuous pass)' do
      expect(described_class::GATED_ROUTES).to include(:login, :create_account)
      expect(described_class::GATED_ROUTES.size).to be >= 10
    end

    # Not an incidental omission: gating logout would strand a signed-in user
    # on a host whose owner flipped the opt-in off.
    it 'never gates logout' do
      expect(described_class::GATED_ROUTES).not_to include(:logout)
    end

    # The classification is by FUNCTION, so — unlike RestrictTo, which
    # reclassifies these three as 'webauthn' when webauthn_verify_account is
    # loaded — nothing about the credential the ceremony mints moves them.
    it 'classifies the create/verify trio as sign-up regardless of the signup ceremony' do
      expect(described_class.axis_for(:create_account)).to eq(:signup)
      expect(described_class.axis_for(:verify_account)).to eq(:signup)
      expect(described_class.axis_for(:verify_account_resend)).to eq(:signup)
    end

    # Password recovery is a sign-in path: the credential it mints is usable on
    # the canonical host, so a host that never opted into sign-in must not mint
    # one, or the opt-in is advisory.
    it 'classifies password recovery as sign-in, not sign-up and not exempt' do
      expect(described_class.axis_for(:reset_password_request)).to eq(:signin)
      expect(described_class.axis_for(:reset_password)).to eq(:signin)
    end
  end

  # ==========================================================================
  # 2. The sign-in axis
  # ==========================================================================

  describe 'sign-in routes on a CUSTOM host' do
    context 'with no SigninConfig at all — the #4163 defect' do
      # Before this gate, POST /auth/login on exactly this host authenticated
      # canonical accounts in full mode while simple mode rejected it.
      described_class::SIGNIN_ROUTES.each do |route|
        it "404s #{route}" do
          expect_rejected(route)
        end
      end
    end

    context 'with a SigninConfig whose master switch is OFF' do
      let(:signin_config) { signin_config_double(enabled: false) }

      it 'still 404s — a disabled record is not an opt-in' do
        expect_rejected(:login)
      end
    end

    context 'with an enabled SigninConfig that opted IN' do
      let(:signin_config) { signin_config_double(signin_enabled: true) }

      described_class::SIGNIN_ROUTES.each do |route|
        it "allows #{route}" do
          expect_allowed(route)
        end
      end
    end

    context 'with an enabled SigninConfig that opted OUT' do
      let(:signin_config) { signin_config_double(signin_enabled: false) }

      it '404s login' do
        expect_rejected(:login)
      end
    end

    # The SSO carve-out inside resolve_signin_enabled_for_custom_domain keeps
    # the /signin PAGE reachable for an SSO-only tenant. It applies to DISPLAY
    # surfaces only, and this gate omits domain_id so it can never fire here:
    # SSO does not flow through POST /auth/login, so honoring the carve-out
    # would re-open the very credential submission ADR-024 closes.
    it 'does not inherit the display SSO carve-out' do
      allow(Onetime::CustomDomain::SsoConfig).to receive(:tenant_sso_available_for?).and_return(true)

      expect_rejected(:login)
      expect(Onetime::CustomDomain::SsoConfig).not_to have_received(:tenant_sso_available_for?)
    end
  end

  describe 'sign-in routes on an OPERATOR host' do
    %i[canonical subdomain].each do |strategy|
      context "on #{strategy.inspect}" do
        it 'follows the global default when sign-in is enabled' do
          expect_allowed(:login, strategy: strategy)
        end

        context 'with AUTH_SIGNIN off' do
          let(:auth_settings) { { 'enabled' => true, 'signin' => false, 'signup' => true } }

          it '404s — the global kill switch reaches the operator host too' do
            expect_rejected(:login, strategy: strategy)
          end
        end

        context 'with the AUTH_ENABLED master switch off' do
          let(:auth_settings) { { 'enabled' => false, 'signin' => true, 'signup' => true } }

          it '404s' do
            expect_rejected(:login, strategy: strategy)
          end
        end
      end
    end

    # The branch is chosen by a POSITIVE operator test
    # (ADR-024#operator-defaults-require-positive-classification), so the
    # :invalid a failing domain-index read manufactures for a REAL customer
    # domain cannot inherit the operator's global sign-in default.
    [:invalid, nil].each do |strategy|
      it "404s login on #{strategy.inspect} — an unplaceable host is not the operator's" do
        expect_rejected(:login, strategy: strategy)
      end
    end
  end

  describe 'the email-auth AND' do
    let(:signin_config) { signin_config_double(signin_enabled: true, email_auth_enabled: tenant_email_auth) }
    let(:tenant_email_auth) { true }

    context 'when the tenant turned magic links off but kept password sign-in' do
      let(:tenant_email_auth) { false }

      described_class::EMAIL_AUTH_ROUTES.each do |route|
        it "404s #{route}" do
          expect_rejected(route)
        end
      end

      it 'leaves the password sign-in routes reachable — the AND is per route, not per host' do
        expect_allowed(:login)
        expect_allowed(:reset_password_request)
      end
    end

    context 'when magic links are disabled INSTALL-wide' do
      let(:email_auth_global) { false }

      it '404s email_auth_request even though the host opted into sign-in' do
        expect_rejected(:email_auth_request)
      end
    end

    context 'when both are on' do
      it 'allows the magic-link routes' do
        expect_allowed(:email_auth_request)
        expect_allowed(:email_auth)
      end
    end

    # Multi-phase login can dispatch a magic link from the LOGIN route. That
    # path is closed at before_email_auth_request (config/hooks/restrict_to.rb),
    # the one chokepoint both entry points share — so :login is deliberately not
    # in EMAIL_AUTH_ROUTES and must not start consulting the magic-link flag.
    it 'does not AND the email-auth flag into the login route' do
      expect(described_class::EMAIL_AUTH_ROUTES).not_to include(:login)
    end
  end

  # ==========================================================================
  # 3. The sign-up axis
  # ==========================================================================

  describe 'sign-up routes on a CUSTOM host' do
    context 'with no SignupConfig' do
      described_class::SIGNUP_ROUTES.each do |route|
        it "404s #{route}" do
          expect_rejected(route)
        end
      end
    end

    context 'with an enabled SignupConfig that opted IN' do
      let(:signup_config) { signup_config_double(signup_enabled: true) }

      described_class::SIGNUP_ROUTES.each do |route|
        it "allows #{route}" do
          expect_allowed(route)
        end
      end

      # The two axes are independent: a host may accept account creation while
      # its sign-in opt-in is absent (and vice versa). Reading the wrong config
      # for an axis would show up here.
      it 'does not let the sign-up opt-in open the sign-in routes' do
        expect_rejected(:login)
      end
    end

    context 'with an enabled SignupConfig that opted OUT' do
      let(:signup_config) { signup_config_double(signup_enabled: false) }

      it '404s create_account' do
        expect_rejected(:create_account)
      end
    end

    context 'with a sign-in opt-in but NO sign-up opt-in' do
      let(:signin_config) { signin_config_double(signin_enabled: true) }

      it 'still 404s create_account — sign-in does not imply sign-up' do
        expect_rejected(:create_account)
        expect_allowed(:login)
      end
    end
  end

  describe 'sign-up routes on an OPERATOR host' do
    it 'follows the global default' do
      expect_allowed(:create_account, strategy: :canonical)
    end

    context 'with AUTH_SIGNUP off' do
      let(:auth_settings) { { 'enabled' => true, 'signin' => true, 'signup' => false } }

      it '404s create_account but leaves sign-in alone — the flags are separate' do
        expect_rejected(:create_account, strategy: :canonical)
        expect_allowed(:login, strategy: :canonical)
      end
    end
  end

  # ==========================================================================
  # 4. Exemptions
  # ==========================================================================

  describe 'routes outside this axis' do
    it 'never touches an exempt route, even on a host that opted into nothing' do
      described_class::UNGATED_ROUTES.each do |route|
        expect(gate(route)).to be_nil,
          "#{route} is documented as exempt (account-scoped / second factor / logout) but was rejected"
      end
    end

    # Second-factor ceremonies are a property of the ACCOUNT (#4138), not of the
    # request host. Gating them would lock out a user who already presented a
    # first factor this host permitted.
    it 'leaves the second-factor ceremonies reachable' do
      expect(gate(:otp_auth)).to be_nil
      expect(gate(:webauthn_auth)).to be_nil
      expect(gate(:recovery_auth)).to be_nil
    end
  end

  describe 'internal requests' do
    # Rodauth's internal_request feature synthesizes a bare env with no Host and
    # no DomainStrategy classification, and handle_internal_request calls
    # before_rodauth directly — so this guard is load-bearing, not defensive.
    # Invite signup autologin is the flow that breaks without it.
    it 'is skipped for an internal sign-in request' do
      expect(gate(:login, internal: true)).to be_nil
    end

    it 'is skipped for an internal sign-up request' do
      expect(gate(:create_account, internal: true)).to be_nil
    end

    it 'is skipped even when the policy read would have raised' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with(display_domain).and_raise(Redis::BaseError, 'lookup unavailable')

      expect(gate(:login, internal: true)).to be_nil
    end
  end

  # ==========================================================================
  # 5. Reject shape and logging
  # ==========================================================================

  describe 'the reject' do
    it 'is byte-identical to the restrict_to gate — the shape cannot leak which fired' do
      expect(described_class.not_found_response).to eq(Auth::RestrictTo.not_found_response)
    end

    it 'carries the router shared body, so a gated route reads as an undefined one' do
      _status, headers, body = gate(:login)

      expect(headers).to eq('content-type' => 'application/json')
      expect(JSON.parse(body.first)).to eq(JSON.parse(JSON.generate(Auth::ErrorTranslator::NOT_FOUND_BODY)))
    end

    it 'logs the rejection with the route and the host classification' do
      gate(:create_account)

      expect(Auth::Logging).to have_received(:log_auth_event).with(
        :signin_gate_route_rejected,
        hash_including(level: :info, route: :create_account, axis: :signup, domain_strategy: :custom),
      )
    end

    it 'logs nothing when it allows through' do
      gate(:login, strategy: :canonical)

      expect(Auth::Logging).not_to have_received(:log_auth_event)
    end
  end

  # ==========================================================================
  # 6. Unreadable policy — 503, never a guess
  # ==========================================================================
  #
  # Two datastore reads back each verdict on a custom host (the CustomDomain
  # identity, then the per-domain config), so this path is reached by a
  # transient blip and not only by a real outage. A 404 here would be the gate
  # claiming an opt-in it never managed to look up; the global default would be
  # the widening #4157 closed, since the SAME blip is what makes DomainStrategy
  # answer :invalid for a real customer domain.
  #
  describe 'lookup failures' do
    shared_examples 'fails closed with 503' do |route, error|
      it "raises #{error} for #{route}" do
        expect { gate(route) }.to raise_error(error)
      end
    end

    context 'when the CustomDomain identity read raises' do
      before do
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .with(display_domain).and_raise(Redis::BaseError, 'lookup unavailable')
      end

      include_examples 'fails closed with 503', :login, Onetime::SigninPolicyUnavailable
      include_examples 'fails closed with 503', :create_account, Onetime::SignupPolicyUnavailable

      it 'logs the failure at error — an auth surface is down and it must alert' do
        expect { gate(:login) }.to raise_error(Onetime::SigninPolicyUnavailable)

        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:signin_gate_policy_lookup_failed, hash_including(level: :error, axis: :signin))
      end

      it 'carries a retry_after so the edge can hint a back-off' do
        expect { gate(:login) }.to raise_error(Onetime::SigninPolicyUnavailable) { |ex|
          expect(ex.to_h[:error_type]).to eq('SigninPolicyUnavailable')
          expect(ex.to_h[:retry_after]).to be_a(Integer)
        }
      end
    end

    context 'when the per-domain config read raises' do
      before do
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
          .with(domain_id).and_raise(Redis::BaseError, 'config unavailable')
        allow(Onetime::CustomDomain::SignupConfig).to receive(:find_by_domain_id)
          .with(domain_id).and_raise(Redis::BaseError, 'config unavailable')
      end

      include_examples 'fails closed with 503', :login, Onetime::SigninPolicyUnavailable
      include_examples 'fails closed with 503', :create_account, Onetime::SignupPolicyUnavailable
    end

    # The POSITIVE operator test, stated as the property rather than a table
    # cell: :invalid is exactly what DomainStrategy answers for a real customer
    # domain when the same blip broke its own read, so it must fail closed with
    # the custom hosts and NOT inherit the operator's global default.
    context 'on a host that could not be classified' do
      before do
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .with(display_domain).and_raise(Redis::BaseError, 'lookup unavailable')
      end

      [:invalid, nil].each do |strategy|
        it "raises rather than inheriting the operator default on #{strategy.inspect}" do
          expect { gate(:login, strategy: strategy) }
            .to raise_error(Onetime::SigninPolicyUnavailable)
          expect { gate(:create_account, strategy: strategy) }
            .to raise_error(Onetime::SignupPolicyUnavailable)
        end
      end
    end

    # An operator host's policy is in-memory config, so the failed read cost it
    # nothing: nil is the only answer it could ever have had, and resolution
    # proceeds against the global setting exactly as it always would.
    context 'on an operator host' do
      before do
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .with(display_domain).and_raise(Redis::BaseError, 'lookup unavailable')
      end

      %i[canonical subdomain].each do |strategy|
        it "resolves from the in-memory global on #{strategy.inspect}" do
          expect_allowed(:login, strategy: strategy)
          expect_allowed(:create_account, strategy: strategy)
        end
      end

      context 'with AUTH_SIGNIN off' do
        let(:auth_settings) { { 'enabled' => true, 'signin' => false, 'signup' => true } }

        it 'still enforces the global — the carve-out is not an allow' do
          expect_rejected(:login, strategy: :canonical)
        end
      end
    end

    it 'does not reach the datastore at all for an exempt route' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with(display_domain).and_raise(Redis::BaseError, 'lookup unavailable')

      expect(gate(:logout)).to be_nil
      expect(gate(:otp_auth)).to be_nil
    end
  end
end
