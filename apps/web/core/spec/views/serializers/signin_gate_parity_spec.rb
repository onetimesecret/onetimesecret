# apps/web/core/spec/views/serializers/signin_gate_parity_spec.rb
#
# frozen_string_literal: true

# FULL-MODE GATE <-> SIMPLE-MODE GATE PARITY for the sign-in / sign-up OPT-IN
# axis (ADR-024#display-runtime-parity,
# ADR-024#operator-defaults-require-positive-classification,
# ADR-034#resolution-is-model-owned, #4163).
#
# THE DEFECT THIS PINS. Simple mode consults the ADR-024 resolvers at its POST
# handlers (Core::Controllers::Base#signin_enabled? / #signup_enabled?); full
# mode did not — its pre-auth routes are Rodauth's and only the `restrict_to`
# axis was gated. A custom domain with no enabled SigninConfig therefore
# REJECTED POST /signin on a simple-mode install and ACCEPTED POST /auth/login
# on a full-mode one, authenticating canonical accounts. An access control that
# changes with the deployment shape is not an access control.
#
# THE ASSERTION IS THE AGREEMENT ITSELF — the two verdicts are compared to each
# other, not to a table of expected values (the values themselves are pinned by
# signin_signup_classification_parity_spec.rb, which owns the required matrix).
# An edit to either gate that "fixes" one without the other reds this file even
# when it looks locally correct. Both sides reach the same model resolvers, so
# what is actually asserted is that neither side gathers a different INPUT:
# a different `global`, a different config, a different classification, or —
# the one that started this — a domain_id that re-opens the display SSO
# carve-out on a credential POST.
#
# The restrict_to axis has its own parity file next door
# (restrict_to_parity_spec.rb). Same shape, different axis: that one answers
# WHICH method a host may offer, this one whether it may offer sign-in at all.
#
# No datastore and no HTTP: the domain/config lookups are stubbed, because what
# is under test is which inputs each gate gathers and that the two agree.
#
# Run:
#   bundle exec rspec apps/web/core/spec/views/serializers/signin_gate_parity_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../views/serializers'

# The POLICY module only (not config/hooks/restrict_to.rb, which is namespaced
# into Auth::Config and drags the boot chain in) — the same require the auth
# unit spec uses.
require_relative File.join(Onetime::HOME, 'apps', 'web', 'auth', 'signin_gate')

RSpec.describe 'sign-in/sign-up opt-in: full-mode gate vs simple-mode gate parity' do
  # Every value env['onetime.domain_strategy'] can carry at a consumer. :invalid
  # and nil are here because they are what a failing domain-index read
  # manufactures for a REAL customer domain, and they are where a `== :custom`
  # branch widens.
  GATE_PARITY_CLASSIFICATIONS = [:canonical, :subdomain, :custom, :invalid, nil].freeze

  let(:display_domain) { 'secrets.tenant.example.com' }
  let(:domain_id)      { 'domain_4163_parity' }

  let(:custom_domain) { instance_double(Onetime::CustomDomain, identifier: domain_id) }

  let(:auth_settings) { { 'enabled' => true, 'signin' => true, 'signup' => true } }

  let(:signin_config) { nil }
  let(:signup_config) { nil }

  # SSO OFF: the display carve-out has its own section, and leaving it on here
  # would mask the password/email default the whole file is about.
  let(:mock_auth_config) do
    instance_double(
      Onetime::AuthConfig,
      sso_enabled?: false,
      sso_providers: [],
      allow_platform_fallback_for_tenants?: false,
      email_auth_enabled?: true,
      restrict_to: nil,
      restrict_to_available?: true
    )
  end

  before do
    allow(Onetime).to receive(:auth_config).and_return(mock_auth_config)
    allow(OT).to receive(:conf).and_return({ 'site' => { 'authentication' => auth_settings } })

    # BOTH identity reads. The two gates resolve the host through the
    # non-swallowing .from_display_domain (#4157); ConfigSerializer, used in the
    # email-auth section below, still resolves through the fail-open
    # .load_by_display_domain. They are distinct class methods with no alias
    # between them, so stubbing only one leaves the other reading a real (empty)
    # datastore and answering "no tenant config" for every case — which turns
    # the assertions below into assertions about the unconfigured default.
    allow(Onetime::CustomDomain).to receive(:from_display_domain)
      .with(display_domain).and_return(custom_domain)
    allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
      .with(display_domain).and_return(custom_domain)
    allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
      .with(domain_id).and_return(signin_config)
    allow(Onetime::CustomDomain::SignupConfig).to receive(:find_by_domain_id)
      .with(domain_id).and_return(signup_config)
    allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
      .with(domain_id).and_return(nil)
  end

  # ---------------------------------------------------------------- surfaces

  # SIMPLE MODE: the Core POST handlers, reached exactly as a request reaches
  # them — through req.env['onetime.domain_strategy'].
  let(:controller_class) do
    Class.new do
      include Core::Controllers::Base

      def initialize(env)
        @req = Struct.new(:env).new(env)
      end
    end
  end

  def env_for(strategy)
    {
      'onetime.domain_strategy' => strategy,
      'onetime.display_domain' => display_domain,
    }
  end

  def simple_signin(strategy)
    controller_class.new(env_for(strategy)).send(:signin_enabled?)
  end

  def simple_signup(strategy)
    controller_class.new(env_for(strategy)).send(:signup_enabled?)
  end

  # FULL MODE: the before_rodauth gate's decision, minus the halt.
  def full_signin(strategy)
    Auth::SigninGate.signin_allowed?(env_for(strategy))
  end

  def full_signup(strategy)
    Auth::SigninGate.signup_allowed?(env_for(strategy))
  end

  # THE assertion. Everything below sets up a scenario and calls this.
  def expect_parity(strategy)
    expect(full_signin(strategy)).to be(simple_signin(strategy)),
      "sign-in verdicts diverge on #{strategy.inspect}: " \
      "full=#{full_signin(strategy)} simple=#{simple_signin(strategy)}"
    expect(full_signup(strategy)).to be(simple_signup(strategy)),
      "sign-up verdicts diverge on #{strategy.inspect}: " \
      "full=#{full_signup(strategy)} simple=#{simple_signup(strategy)}"
  end

  # ------------------------------------------------------------- the matrix

  describe 'host classification x tenant config' do
    def signin_config_double(enabled:, opt_in:)
      instance_double(
        Onetime::CustomDomain::SigninConfig,
        domain_id: domain_id,
        enabled?: enabled,
        signin_enabled?: opt_in,
        email_auth_enabled?: true,
        sso_enabled?: false,
        restrict_to: nil
      )
    end

    def signup_config_double(enabled:, opt_in:)
      instance_double(
        Onetime::CustomDomain::SignupConfig,
        domain_id: domain_id,
        enabled?: enabled,
        signup_enabled?: opt_in
      )
    end

    # The four states a per-domain policy can be in. The interesting one is the
    # first: it is the shape #4163 was filed for, and the two modes disagreed
    # on it in exactly one direction.
    {
      'no per-domain config' => { signin: nil, signup: nil },
      'a disabled record (not an opt-in)' => { signin: [false, true], signup: [false, true] },
      'an enabled record that opted IN' => { signin: [true, true], signup: [true, true] },
      'an enabled record that opted OUT' => { signin: [true, false], signup: [true, false] },
    }.each do |label, state|
      context "with #{label}" do
        let(:signin_config) do
          state[:signin] && signin_config_double(enabled: state[:signin][0], opt_in: state[:signin][1])
        end
        let(:signup_config) do
          state[:signup] && signup_config_double(enabled: state[:signup][0], opt_in: state[:signup][1])
        end

        GATE_PARITY_CLASSIFICATIONS.each do |strategy|
          it "agrees on #{strategy.inspect}" do
            expect_parity(strategy)
          end
        end
      end
    end
  end

  # The property, stated once rather than left implicit in the matrix.
  describe 'the #4163 defect itself' do
    it 'a custom domain with no opt-in rejects sign-in in BOTH modes' do
      expect(simple_signin(:custom)).to be(false)
      expect(full_signin(:custom)).to be(false)
    end

    it 'and rejects sign-up in both' do
      expect(simple_signup(:custom)).to be(false)
      expect(full_signup(:custom)).to be(false)
    end

    it 'while the operator host is untouched in both' do
      expect(simple_signin(:canonical)).to be(true)
      expect(full_signin(:canonical)).to be(true)
      expect(simple_signup(:canonical)).to be(true)
      expect(full_signup(:canonical)).to be(true)
    end
  end

  # ------------------------------------------------------- the display carve-out

  # resolve_signin_enabled_for_custom_domain has two modes and the full-mode
  # gate must pick the same one simple mode picks. An SSO-only tenant reports
  # sign-in AVAILABLE to DISPLAY surfaces (its /signin page works through the
  # omniauth routes), and strictly DISABLED to the credential POST gates. A
  # full-mode gate that passed domain_id would re-open precisely the password
  # submission ADR-024 closes — and would do it on a host where simple mode
  # rejects.
  describe 'the SSO carve-out reaches neither gate' do
    before do
      allow(Onetime::CustomDomain::SsoConfig)
        .to receive(:tenant_sso_available_for?).and_return(true)
    end

    [:custom, :invalid, nil].each do |strategy|
      it "stays closed on #{strategy.inspect} in both modes" do
        expect_parity(strategy)
        expect(full_signin(strategy)).to be(false)
      end
    end

    it 'never consults the tenant SSO predicate from the full-mode gate' do
      full_signin(:custom)

      expect(Onetime::CustomDomain::SsoConfig).not_to have_received(:tenant_sso_available_for?)
    end
  end

  # ------------------------------------------------------------ kill switches

  describe 'global kill switches' do
    {
      'AUTH_ENABLED off' => { 'enabled' => false, 'signin' => true, 'signup' => true },
      'AUTH_SIGNIN off' => { 'enabled' => true, 'signin' => false, 'signup' => true },
      'AUTH_SIGNUP off' => { 'enabled' => true, 'signin' => true, 'signup' => false },
    }.each do |label, settings|
      context "with #{label}" do
        let(:auth_settings) { settings }

        GATE_PARITY_CLASSIFICATIONS.each do |strategy|
          it "agrees on #{strategy.inspect}" do
            expect_parity(strategy)
          end
        end
      end
    end

    # The gate reads the global itself (global_signin_enabled with no argument)
    # while the controller passes site.authentication in. Same source, two call
    # shapes — this is the assertion that they stay the same VALUE.
    it 'reads the same global input on both sides' do
      expect(Onetime::CustomDomain::SigninConfig.global_signin_enabled)
        .to be(Onetime::CustomDomain::SigninConfig.global_signin_enabled(auth_settings))
      expect(Onetime::CustomDomain::SignupConfig.global_signup_enabled)
        .to be(Onetime::CustomDomain::SignupConfig.global_signup_enabled(auth_settings))
    end
  end

  # --------------------------------------------------------- unreadable policy

  # A blip on the hot path must produce the SAME answer in both modes: 503 on
  # any host not positively the operator's, and the still-known in-memory
  # global everywhere else. The mode-dependent version of this is what #4157
  # closed for simple mode; #4163 is the other half.
  describe 'lookup failures' do
    before do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with(display_domain).and_raise(Redis::BaseError, 'lookup unavailable')
      allow(Auth::Logging).to receive(:log_auth_event)
    end

    [:custom, :invalid, nil].each do |strategy|
      it "both modes raise SigninPolicyUnavailable on #{strategy.inspect}" do
        expect { simple_signin(strategy) }.to raise_error(Onetime::SigninPolicyUnavailable)
        expect { full_signin(strategy) }.to raise_error(Onetime::SigninPolicyUnavailable)
      end

      it "both modes raise SignupPolicyUnavailable on #{strategy.inspect}" do
        expect { simple_signup(strategy) }.to raise_error(Onetime::SignupPolicyUnavailable)
        expect { full_signup(strategy) }.to raise_error(Onetime::SignupPolicyUnavailable)
      end
    end

    %i[canonical subdomain].each do |strategy|
      it "both modes resolve from the in-memory global on #{strategy.inspect}" do
        expect_parity(strategy)
        expect(full_signin(strategy)).to be(true)
      end

      context 'with AUTH_SIGNIN off' do
        let(:auth_settings) { { 'enabled' => true, 'signin' => false, 'signup' => true } }

        it "both modes still enforce the global on #{strategy.inspect}" do
          expect_parity(strategy)
          expect(full_signin(strategy)).to be(false)
        end
      end
    end
  end

  # ------------------------------------------------------------- email auth

  # The magic-link routes carry a second AND: the per-domain override can turn
  # magic links off while leaving password sign-in on. Its display consumer is
  # ConfigSerializer#resolve_email_auth (the button), so the claim here is the
  # same one the rest of the file makes — the route and the button read one
  # resolver with one set of inputs.
  describe 'the email-auth AND on the magic-link routes' do
    let(:tenant_email_auth) { true }
    let(:signin_config) do
      instance_double(
        Onetime::CustomDomain::SigninConfig,
        domain_id: domain_id,
        enabled?: true,
        signin_enabled?: true,
        email_auth_enabled?: tenant_email_auth,
        sso_enabled?: false,
        restrict_to: nil
      )
    end

    def view_vars_for(strategy)
      {
        'site' => { 'authentication' => auth_settings },
        'domain_strategy' => strategy,
        'display_domain' => display_domain,
      }
    end

    def gate_email_auth(strategy)
      Auth::SigninGate.allowed?(env_for(strategy), :signin, :email_auth_request)
    end

    def display_email_auth(strategy)
      Core::Views::ConfigSerializer.resolve_email_auth(view_vars_for(strategy))
    end

    GATE_PARITY_CLASSIFICATIONS.each do |strategy|
      it "agrees with signin AND the display magic-link answer on #{strategy.inspect}" do
        expect(gate_email_auth(strategy))
          .to be(simple_signin(strategy) && display_email_auth(strategy))
      end
    end

    context 'when the tenant turned magic links off' do
      let(:tenant_email_auth) { false }

      it 'closes the magic-link route while password sign-in stays open' do
        expect(gate_email_auth(:custom)).to be(false)
        expect(full_signin(:custom)).to be(true)
        expect(simple_signin(:custom)).to be(true)
      end
    end

    context 'when magic links are disabled install-wide' do
      before { allow(mock_auth_config).to receive(:email_auth_enabled?).and_return(false) }

      it 'closes the magic-link route on the operator host too' do
        expect(gate_email_auth(:canonical)).to be(false)
        expect(display_email_auth(:canonical)).to be(false)
      end
    end
  end

  # ------------------------------------------------------ String classifications

  # StrategyResult metadata is not always a Symbol; operator_host? normalizes
  # with to_sym, and a gate that compared raw values would disagree with one
  # that normalized.
  describe 'String classifications' do
    %w[canonical subdomain custom invalid].each do |strategy|
      it "agrees on #{strategy.inspect}" do
        expect_parity(strategy)
        expect(full_signin(strategy)).to be(full_signin(strategy.to_sym))
      end
    end
  end
end
