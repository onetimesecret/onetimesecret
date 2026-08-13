# apps/web/core/spec/views/serializers/signin_signup_classification_parity_spec.rb
#
# frozen_string_literal: true

# DISPLAY <-> RUNTIME PARITY for the sign-in / sign-up DEFAULT, keyed by the
# request's DomainStrategy classification (ADR-024 A12,
# docs/specs/domain-resolution/domain-resolution.md).
#
# The defect this pins: choosing the auth resolver on `== :custom` picks the
# OPERATOR branch for :invalid and nil, and :invalid is what DomainStrategy
# answers when its own datastore read RAISES for a REAL customer domain. A blip
# therefore handed that domain the operator's global sign-in/sign-up default —
# an availability failure widening authentication access on a domain whose
# owner never opted in. The fix is a POSITIVE test (SigninConfig.operator_host?)
# at policy resolution, applied on BOTH surfaces:
#
#   runtime: Core::Controllers::Base#signin_enabled? / #signup_enabled?
#   display: Core::Views::ConfigSerializer#resolve_signin
#
# Fixing only the runtime gate would leave /signin advertising availability
# while the POST rejects it; fixing only the display would leave the widened
# gate in place. So the matrix below asserts the VALUE per classification AND
# that the two surfaces produce the same value.
#
# The identity predicates (custom_domain_request?, tenant_domain?) deliberately
# stay `== :custom` and are pinned in
# spec/unit/domain_strategy_classification_contract_spec.rb — flipping those
# would hand tenant branding/routing to a genuinely unknown host, which the
# spec text rejects.
#
# No datastore and no HTTP: the domain/config lookups are stubbed, because what
# is under test is which BRANCH each surface takes and that the two agree.
#
# Run:
#   bundle exec rspec apps/web/core/spec/views/serializers/signin_signup_classification_parity_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../views/serializers'

RSpec.describe 'sign-in/sign-up classification polarity (ADR-024 A12)' do
  # Every value env['onetime.domain_strategy'] can carry at a consumer.
  CLASSIFICATIONS_A12 = [:canonical, :subdomain, :custom, :invalid, nil].freeze

  # The required test matrix from docs/specs/domain-resolution/domain-resolution.md,
  # for global auth ENABLED and NO tenant configuration. Only the two
  # classifications a datastore failure can never MANUFACTURE inherit the
  # operator default.
  EXPECTED_A12 = {
    canonical: true,
    subdomain: true,
    custom: false,
    invalid: false,
    nil => false,
  }.freeze

  def expected_for(strategy)
    EXPECTED_A12.fetch(strategy.nil? ? nil : strategy)
  end

  let(:display_domain) { 'secrets.tenant.example.com' }
  let(:domain_id)      { 'domain_a12_1' }

  let(:custom_domain) { instance_double(Onetime::CustomDomain, identifier: domain_id) }

  # Global authentication: enabled for sign-in AND sign-up unless a context
  # overrides it.
  let(:auth_settings) { { 'enabled' => true, 'signin' => true, 'signup' => true } }

  let(:signin_config) { nil }
  let(:signup_config) { nil }
  let(:sso_config)    { nil }

  # SSO OFF by default so the display gate's SSO carve-out cannot mask the
  # password/email default under test. The carve-out has its own section below.
  let(:mock_auth_config) do
    instance_double(
      Onetime::AuthConfig,
      sso_enabled?: false,
      sso_providers: [],
      allow_platform_fallback_for_tenants?: false,
      email_auth_enabled?: false,
      restrict_to: nil,
      restrict_to_available?: true
    )
  end

  before do
    allow(Onetime).to receive(:auth_config).and_return(mock_auth_config)
    allow(OT).to receive(:conf).and_return({ 'site' => { 'authentication' => auth_settings } })

    allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
      .with(display_domain).and_return(custom_domain)
    allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
      .with(domain_id).and_return(signin_config)
    allow(Onetime::CustomDomain::SignupConfig).to receive(:find_by_domain_id)
      .with(domain_id).and_return(signup_config)
    allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
      .with(domain_id).and_return(sso_config)
  end

  # ---------------------------------------------------------------- surfaces

  # The runtime gates, reached exactly as a request reaches them: through
  # req.env['onetime.domain_strategy'].
  let(:controller_class) do
    Class.new do
      include Core::Controllers::Base

      def initialize(env)
        @req = Struct.new(:env).new(env)
      end
    end
  end

  def controller_for(strategy)
    controller_class.new(
      'onetime.domain_strategy' => strategy,
      'onetime.display_domain' => display_domain,
    )
  end

  def runtime_signin(strategy)
    controller_for(strategy).send(:signin_enabled?)
  end

  def runtime_signup(strategy)
    controller_for(strategy).send(:signup_enabled?)
  end

  def view_vars_for(strategy)
    {
      'site' => { 'authentication' => auth_settings },
      'domain_strategy' => strategy,
      'display_domain' => display_domain,
    }
  end

  # The display gate: features.signin in the bootstrap payload.
  def display_signin(strategy)
    Core::Views::ConfigSerializer.resolve_signin(view_vars_for(strategy))
  end

  # THE SIGN-UP DISPLAY SURFACE. There is no classification-keyed one:
  # ConfigSerializer emits no features.signup, and the only serialized sign-up
  # availability is DomainSerializer's branded-masthead link, which is keyed by
  # domain_id and always resolves through the CUSTOM-DOMAIN (default-OFF)
  # resolver. It is included here so the claim "display and runtime agree" is
  # asserted rather than assumed: on every non-operator classification the
  # masthead answer must equal the runtime gate's.
  def display_signup_for_domain
    Core::Views::DomainSerializer.effective_signup_enabled?(domain_id)
  end

  def display_signin_for_domain
    Core::Views::DomainSerializer.effective_signin_enabled?(domain_id)
  end

  # ---------------------------------------------------- the required matrix

  describe 'global auth ENABLED, no tenant configuration' do
    CLASSIFICATIONS_A12.each do |strategy|
      context "on #{strategy.inspect}" do
        let(:expected) { EXPECTED_A12.fetch(strategy) }

        it "resolves sign-in #{EXPECTED_A12.fetch(strategy) ? 'enabled' : 'disabled'} at the runtime gate" do
          expect(runtime_signin(strategy)).to be(expected)
        end

        it "resolves sign-up #{EXPECTED_A12.fetch(strategy) ? 'enabled' : 'disabled'} at the runtime gate" do
          expect(runtime_signup(strategy)).to be(expected)
        end

        it "resolves sign-in #{EXPECTED_A12.fetch(strategy) ? 'enabled' : 'disabled'} at the display gate" do
          expect(display_signin(strategy)).to be(expected)
        end

        it 'agrees between display and runtime for sign-in' do
          expect(display_signin(strategy)).to be(runtime_signin(strategy))
        end
      end
    end

    # The row the whole fix exists for, stated as the security property rather
    # than as a table cell.
    it ':invalid does NOT inherit the operator default — a blip cannot widen access' do
      expect(runtime_signin(:invalid)).to be(false)
      expect(runtime_signup(:invalid)).to be(false)
      expect(display_signin(:invalid)).to be(false)

      # ...while the operator's own host is untouched by the same rule.
      expect(runtime_signin(:canonical)).to be(true)
      expect(runtime_signup(:canonical)).to be(true)
      expect(display_signin(:canonical)).to be(true)
    end

    it 'the branded sign-up display surface is default-OFF, matching every non-operator runtime answer' do
      expect(display_signup_for_domain).to be(false)
      expect(runtime_signup(:custom)).to be(false)
      expect(runtime_signup(:invalid)).to be(false)
      expect(runtime_signup(nil)).to be(false)
    end
  end

  # --------------------------------------------------- global kill switch

  describe 'global auth DISABLED' do
    let(:auth_settings) { { 'enabled' => false, 'signin' => true, 'signup' => true } }

    CLASSIFICATIONS_A12.each do |strategy|
      it "stays disabled for #{strategy.inspect} on both surfaces" do
        expect(runtime_signin(strategy)).to be(false)
        expect(runtime_signup(strategy)).to be(false)
        expect(display_signin(strategy)).to be(false)
      end
    end
  end

  describe 'AUTH_SIGNIN / AUTH_SIGNUP off with the master switch on' do
    let(:auth_settings) { { 'enabled' => true, 'signin' => false, 'signup' => false } }

    CLASSIFICATIONS_A12.each do |strategy|
      it "stays disabled for #{strategy.inspect} on both surfaces" do
        expect(runtime_signin(strategy)).to be(false)
        expect(runtime_signup(strategy)).to be(false)
        expect(display_signin(strategy)).to be(false)
      end
    end
  end

  # ------------------------------------------------ tenant config narrowing

  describe 'an enabled tenant config can only NARROW' do
    let(:signin_config) do
      instance_double(
        Onetime::CustomDomain::SigninConfig,
        domain_id: domain_id,
        enabled?: true,
        signin_enabled?: signin_opt_in,
        email_auth_enabled?: false,
        sso_enabled?: false,
        restrict_to: nil
      )
    end

    let(:signup_config) do
      instance_double(
        Onetime::CustomDomain::SignupConfig,
        domain_id: domain_id,
        enabled?: true,
        signup_enabled?: signup_opt_in
      )
    end

    context 'when the tenant turns sign-in/sign-up OFF' do
      let(:signin_opt_in) { false }
      let(:signup_opt_in) { false }

      CLASSIFICATIONS_A12.each do |strategy|
        it "narrows #{strategy.inspect} to disabled, INCLUDING the operator's own host" do
          expect(runtime_signin(strategy)).to be(false)
          expect(runtime_signup(strategy)).to be(false)
          expect(display_signin(strategy)).to be(false)
        end
      end
    end

    context 'when the tenant turns sign-in/sign-up ON but the install has it off' do
      let(:signin_opt_in)  { true }
      let(:signup_opt_in)  { true }
      let(:auth_settings)  { { 'enabled' => true, 'signin' => false, 'signup' => false } }

      CLASSIFICATIONS_A12.each do |strategy|
        it "cannot widen #{strategy.inspect} back to enabled" do
          expect(runtime_signin(strategy)).to be(false)
          expect(runtime_signup(strategy)).to be(false)
          expect(display_signin(strategy)).to be(false)
        end
      end
    end

    # THE COUNTERWEIGHT to the fail-closed rule: it must not make explicit
    # enablement unreachable. A host misclassified :invalid whose tenant config
    # WAS read successfully still follows that tenant's own policy.
    context 'when the tenant explicitly ENABLES and the config read succeeded' do
      let(:signin_opt_in) { true }
      let(:signup_opt_in) { true }

      it ':invalid follows the tenant policy — enabled, not default-OFF' do
        expect(runtime_signin(:invalid)).to be(true)
        expect(runtime_signup(:invalid)).to be(true)
        expect(display_signin(:invalid)).to be(true)
      end

      it ':custom follows it identically — the two are not distinguished once a config is readable' do
        expect(runtime_signin(:custom)).to be(true)
        expect(runtime_signup(:custom)).to be(true)
        expect(display_signin(:custom)).to be(true)
      end

      it 'nil follows it too' do
        expect(runtime_signin(nil)).to be(true)
        expect(runtime_signup(nil)).to be(true)
      end

      it 'the branded masthead surfaces agree' do
        expect(display_signup_for_domain).to be(true)
        expect(display_signin_for_domain).to be(true)
      end
    end
  end

  # --------------------------------------------------- String classifications

  # StrategyResult metadata is not always a Symbol; operator_host? normalizes
  # with to_sym, so the string forms must resolve identically.
  describe 'String classifications' do
    it "'canonical' behaves like :canonical" do
      expect(runtime_signin('canonical')).to be(runtime_signin(:canonical))
      expect(runtime_signup('canonical')).to be(runtime_signup(:canonical))
      expect(runtime_signin('canonical')).to be(true)
    end

    it "'subdomain' behaves like :subdomain" do
      expect(runtime_signin('subdomain')).to be(true)
      expect(runtime_signup('subdomain')).to be(true)
    end

    it "'custom' behaves like :custom" do
      expect(runtime_signin('custom')).to be(false)
      expect(runtime_signup('custom')).to be(false)
    end

    it "'invalid' behaves like :invalid" do
      expect(runtime_signin('invalid')).to be(false)
      expect(runtime_signup('invalid')).to be(false)
    end

    it 'the display gate normalizes the same way' do
      expect(display_signin('canonical')).to be(true)
      expect(display_signin('custom')).to be(false)
      expect(display_signin('invalid')).to be(false)
    end
  end

  # ------------------------------------------------------- SSO distinction

  # Spec refinement 3: resolve_signin_enabled_for_custom_domain has two modes,
  # and the classification-aware change must not collapse them.
  #
  #   display gate  (domain_id passed): an SSO-only tenant reports AVAILABLE —
  #     its /signin page works through the omniauth routes.
  #   POST gate     (domain_id omitted): strictly disabled — SSO never flows
  #     through POST /signin, so the password/email handler stays closed.
  #
  # The asymmetry must hold for :invalid exactly as for :custom: a
  # misclassified SSO-only tenant must not lose its working sign-in link.
  describe 'sign-in SSO carve-out' do
    let(:global) { Onetime::CustomDomain::SigninConfig.global_signin_enabled(auth_settings) }

    before do
      allow(Onetime::CustomDomain::SsoConfig)
        .to receive(:tenant_sso_available_for?).and_return(true)
    end

    def resolver_with_domain_id(strategy)
      Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_request(
        global, nil, domain_strategy: strategy, domain_id: domain_id
      )
    end

    def resolver_without_domain_id(strategy)
      Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_request(
        global, nil, domain_strategy: strategy
      )
    end

    [:custom, :invalid, nil].each do |strategy|
      it "reports sign-in AVAILABLE for an SSO-only tenant on #{strategy.inspect} when domain_id is passed" do
        expect(resolver_with_domain_id(strategy)).to be(true)
      end

      it "reports sign-in DISABLED for the same tenant on #{strategy.inspect} when domain_id is omitted" do
        expect(resolver_without_domain_id(strategy)).to be(false)
      end
    end

    it 'the POST gate omits domain_id, so an SSO-only tenant cannot POST credentials' do
      expect(runtime_signin(:custom)).to be(false)
      expect(runtime_signin(:invalid)).to be(false)
    end

    it 'the carve-out is irrelevant on an operator host — the global default already applies' do
      expect(resolver_with_domain_id(:canonical)).to be(true)
      expect(resolver_without_domain_id(:canonical)).to be(true)
    end

    # The serialized /signin page reaches the same conclusion by its own route
    # (sso_available? / build_sso_config) rather than through the domain_id
    # carve-out, so it is pinned separately.
    context 'with an enabled tenant SsoConfig' do
      let(:sso_config) do
        instance_double(
          Onetime::CustomDomain::SsoConfig,
          domain_id: domain_id,
          enabled?: true,
          enforce_sso_only?: false,
          platform_route_name: 'oidc',
          display_name: 'Tenant SSO'
        )
      end

      it 'keeps the /signin page available on :custom and :invalid alike' do
        expect(display_signin(:custom)).to be(true)
        expect(display_signin(:invalid)).to be(true)
      end

      it 'and the branded masthead link agrees with the page' do
        expect(display_signin_for_domain).to be(true)
      end
    end
  end

  # ------------------------------------------- platform SSO fallback (closed)

  # A12 ONE LAYER DOWN, CLOSED. Found while writing the matrix above and fixed
  # in the same pass. resolve_signin moved to operator_domain?, but the SSO
  # surface it delegates to still keyed on the IDENTITY predicate:
  # build_sso_config's `tenant_domain?(view_vars) && !allow_platform_fallback?`
  # guard. An operator who withheld platform fallback from tenants had that
  # policy applied to :custom and SKIPPED for :invalid and nil — so a real
  # customer domain misclassified by a datastore blip was offered the platform
  # SSO providers (and features.signin true) its correct classification denies.
  # Platform omniauth routes are host-independent, so that was a working
  # sign-in method granted by an availability failure, not a rendering detail.
  #
  # The guard is a POLICY decision — "may this host borrow the platform's SSO
  # providers" — so it takes the positive test like the sign-in gates. What is
  # NOT flipped is the tenant-vs-platform SELECTION above it
  # (resolve_tenant_sso_config, keyed on domain_id): that is genuine identity,
  # and flipping tenant_domain? wholesale would have broken it. Splitting the
  # two uses is what makes the fix safe, so both halves are pinned here.
  #
  # This block is deliberately kept rather than deleted, with its expectations
  # inverted: a revert to the identity predicate reds here with the history
  # attached.
  describe 'platform SSO fallback takes the positive operator test' do
    let(:mock_auth_config) do
      instance_double(
        Onetime::AuthConfig,
        sso_enabled?: true,
        sso_providers: [{ 'route_name' => 'oidc', 'display_name' => 'Platform SSO' }],
        allow_platform_fallback_for_tenants?: fallback_allowed,
        email_auth_enabled?: false,
        restrict_to: nil,
        restrict_to_available?: true
      )
    end

    def sso_payload(strategy)
      Core::Views::ConfigSerializer.build_sso_config(view_vars_for(strategy))
    end

    context 'when the operator WITHHOLDS platform fallback from tenants' do
      let(:fallback_allowed) { false }

      [:custom, :invalid, nil].each do |strategy|
        it "withholds platform SSO on #{strategy.inspect} — a blip cannot grant a method the operator denied" do
          expect(sso_payload(strategy)['enabled']).to be(false)
          expect(sso_payload(strategy)['providers']).to eq([])
          expect(display_signin(strategy)).to be(false)
        end
      end

      [:canonical, :subdomain].each do |strategy|
        it "still offers platform SSO on #{strategy.inspect} — the operator's own hosts were never the target" do
          expect(sso_payload(strategy)['enabled']).to be(true)
          expect(display_signin(strategy)).to be(true)
        end
      end

      it 'agrees with the runtime password/email gate on every classification' do
        CLASSIFICATIONS_A12.each do |strategy|
          expect(display_signin(strategy)).to be(runtime_signin(strategy))
        end
      end
    end

    # THE COUNTERWEIGHT: the positive test must not manufacture a withholding
    # the operator never configured. With fallback allowed, every
    # classification keeps the platform providers it had before the fix.
    context 'when the operator ALLOWS platform fallback' do
      let(:fallback_allowed) { true }

      CLASSIFICATIONS_A12.each do |strategy|
        it "offers platform SSO on #{strategy.inspect}" do
          expect(sso_payload(strategy)['enabled']).to be(true)
        end
      end

      # The one surviving display/runtime asymmetry, and it is the documented
      # SSO one: the page stays reachable because its omniauth providers work,
      # while POST /signin (password/email only) stays closed.
      it 'keeps the /signin page reachable on a tenant-safe host while the POST gate stays closed' do
        expect(display_signin(:invalid)).to be(true)
        expect(runtime_signin(:invalid)).to be(false)
      end
    end

    # SELECTION IS UNTOUCHED: an enabled tenant SsoConfig is resolved by
    # domain_id, before the policy guard runs, so it is returned on :custom and
    # :invalid alike regardless of the fallback policy.
    context 'with a tenant SsoConfig and fallback withheld' do
      let(:fallback_allowed) { false }
      let(:sso_config) do
        instance_double(
          Onetime::CustomDomain::SsoConfig,
          domain_id: domain_id,
          enabled?: true,
          enforce_sso_only?: false,
          platform_route_name: 'oidc',
          display_name: 'Tenant SSO'
        )
      end

      before do
        allow(Onetime::CustomDomain::SsoConfig)
          .to receive(:tenant_sso_available_for?).and_return(true)
      end

      [:custom, :invalid].each do |strategy|
        it "returns the TENANT's own providers on #{strategy.inspect}, not the platform's" do
          expect(sso_payload(strategy)['enabled']).to be(true)
          expect(sso_payload(strategy)['providers'].first['display_name']).to eq('Tenant SSO')
        end
      end
    end
  end

  # ------------------------------------------- unreadable policy fails closed

  # Spec refinement 4. "Disabled unless explicitly enabled" requires actually
  # READING the tenant policy. If that read fails, the application cannot
  # establish explicit enablement and must not degrade into the operator
  # default — that is the same widen A12 closes, arriving one layer later.
  describe 'unreadable tenant policy' do
    let(:redis_down) { Redis::BaseError.new('datastore unavailable') }

    context 'when the CustomDomain identity read fails' do
      before do
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
          .with(display_domain).and_raise(redis_down)
      end

      [:custom, :invalid, nil].each do |strategy|
        it "fails closed with SigninPolicyUnavailable on #{strategy.inspect}, never the operator default" do
          expect { runtime_signin(strategy) }
            .to raise_error(Onetime::SigninPolicyUnavailable)
        end
      end

      [:canonical, :subdomain].each do |strategy|
        it "keeps sign-in up on #{strategy.inspect} — no per-domain policy could have applied there" do
          expect(runtime_signin(strategy)).to be(true)
        end
      end
    end

    context 'when the SigninConfig read fails' do
      before do
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
          .with(domain_id).and_raise(redis_down)
      end

      [:custom, :invalid, nil].each do |strategy|
        it "fails closed with SigninPolicyUnavailable on #{strategy.inspect}" do
          expect { runtime_signin(strategy) }
            .to raise_error(Onetime::SigninPolicyUnavailable)
        end
      end

      # The operator hosts still reach the read (custom_domain_id resolves the
      # display domain to a record here), so the carve-out has to be applied at
      # the failure, not skipped by luck.
      [:canonical, :subdomain].each do |strategy|
        it "degrades to the still-known global policy on #{strategy.inspect}" do
          expect(runtime_signin(strategy)).to be(true)
        end
      end
    end

    it 'the failure is a 503-shaped Problem, not the gate\'s ordinary 404 reject' do
      allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
        .with(domain_id).and_raise(redis_down)

      expect { runtime_signin(:invalid) }.to raise_error(Onetime::SigninPolicyUnavailable) { |ex|
        expect(ex.to_h[:error_type]).to eq('SigninPolicyUnavailable')
      }
    end

    # SIGN-UP HALF. Owned by spec/unit/signup_policy_unavailable_spec.rb, which
    # covers the decision owner (SignupConfig.resolve_lookup_failure), the
    # error family, the mixin and the gate. NOT duplicated here. What this file
    # adds is the one claim neither half can make alone: the two surfaces fail
    # closed on the SAME hosts and survive on the same hosts, so a datastore
    # blip cannot leave sign-up open where sign-in is closed or the reverse.
    context 'sign-in and sign-up fail closed together' do
      before do
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
          .with(domain_id).and_raise(redis_down)
        allow(Onetime::CustomDomain::SignupConfig).to receive(:find_by_domain_id)
          .with(domain_id).and_raise(redis_down)
      end

      [:custom, :invalid, nil].each do |strategy|
        it "both raise an AuthPolicyUnavailable on #{strategy.inspect}, neither degrades to the operator default" do
          expect { runtime_signin(strategy) }.to raise_error(Onetime::SigninPolicyUnavailable)
          expect { runtime_signup(strategy) }.to raise_error(Onetime::SignupPolicyUnavailable)
        end
      end

      [:canonical, :subdomain].each do |strategy|
        it "both survive on #{strategy.inspect} — no per-domain policy could have applied there" do
          expect(runtime_signin(strategy)).to be(true)
          expect(runtime_signup(strategy)).to be(true)
        end
      end

      it 'reports the surface that is actually down, not a shared class' do
        expect(Onetime::SignupPolicyUnavailable).not_to be <= Onetime::SigninPolicyUnavailable
        expect(Onetime::SignupPolicyUnavailable.new.to_h[:error_type]).to eq('SignupPolicyUnavailable')
      end
    end
  end
end
