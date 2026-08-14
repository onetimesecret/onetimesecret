# spec/unit/domain_strategy_classification_contract_spec.rb
#
# frozen_string_literal: true

# EXECUTABLE PIN for the consumer table in
# Onetime::Middleware::DomainStrategy's class doc (unresolved — no ADR
# entry covers this asymmetry yet; #4139).
#
# The table is a claim about ~10 INDEPENDENT `== :custom` call sites spread
# across controllers, serializers, view helpers and two API stacks. As prose it
# rots: nothing stops an eleventh consumer from being added with the opposite
# polarity, and nothing makes the existing ten agree. This drives every
# classification through each consumer and pins the resolved answer, so a
# disagreement fails here rather than in review.
#
# The classification that matters is :invalid. It is not only a malformed
# host — DomainStrategy also answers it when its `known_custom_domain?`
# datastore read RAISES (choose_strategy's `rescue StandardError` → nil →
# `|| :invalid`), so a blip classifies a REAL customer domain :invalid. Every
# row below is therefore also a statement about what that blip costs.
#
# nil is included because a code path that never passed through the middleware
# (internal requests, logic invoked outside Rack) reads the env key as nil, and
# the fail-closed rule must treat that like :invalid rather than like canonical.

require 'spec_helper'
require 'onetime/middleware/domain_strategy'
require_relative '../../apps/web/auth/restrict_to'
require_relative '../../apps/api/v1/logic/base'

module DomainStrategyContract
  # Every value env['onetime.domain_strategy'] can carry at a consumer.
  CLASSIFICATIONS = [:canonical, :subdomain, :custom, :invalid, nil].freeze

  # The two classifications a datastore failure can never MANUFACTURE. That
  # one-directional property — not read-freeness, which only :canonical has —
  # is the entire justification for carving them out of a fail-closed rule:
  # operator_host? may be over-strict during an outage, never over-permissive.
  # Pinned at the bottom of this file.
  OPERATOR = [:canonical, :subdomain].freeze
end

RSpec.describe 'DomainStrategy classification contract' do
  def env_for(strategy)
    {
      'onetime.domain_strategy' => strategy,
      'onetime.display_domain' => 'tenant.example.com',
    }
  end

  # ---------------------------------------------------------------- row 1
  #
  # The ONLY positive test in the table. Everything below is `== :custom` and
  # takes its else branch for :invalid/nil; this one refuses to.
  describe 'SigninConfig.operator_host? — the fail-closed carve-out' do
    DomainStrategyContract::CLASSIFICATIONS.each do |strategy|
      expected = DomainStrategyContract::OPERATOR.include?(strategy)

      it "answers #{expected} for #{strategy.inspect}" do
        expect(Onetime::CustomDomain::SigninConfig.operator_host?(strategy)).to be(expected)
      end
    end

    it 'is a POSITIVE test, not `!= :custom` — :invalid can BE a custom domain' do
      expect(Onetime::CustomDomain::SigninConfig.operator_host?(:invalid)).to be(false),
        'a failing domain-index read classifies a real custom domain :invalid; ' \
        'carving out everything non-:custom would hand it the global-only answer'
    end

    it 'accepts a String classification — StrategyResult metadata is not always a Symbol' do
      expect(Onetime::CustomDomain::SigninConfig.operator_host?('canonical')).to be(true)
    end
  end

  # ---------------------------------------------------------------- rows 2-4
  #
  # custom_domain_request? is one line, and it decides the polarity of BOTH
  # auth gates. Its false branch is wider than "not a custom domain".
  describe 'Core::Controllers::Base' do
    let(:controller_class) do
      Class.new do
        include Core::Controllers::Base

        def initialize(env)
          @req = Struct.new(:env).new(env)
        end
      end
    end

    def controller_for(strategy)
      controller_class.new(env_for(strategy))
    end

    describe '#custom_domain_request?' do
      DomainStrategyContract::CLASSIFICATIONS.each do |strategy|
        expected = strategy == :custom

        it "answers #{expected} for #{strategy.inspect}" do
          expect(controller_for(strategy).send(:custom_domain_request?)).to be(expected)
        end
      end
    end

    # WHICH RESOLVER IS CALLED is the whole point — the two have OPPOSITE
    # defaults. resolve_*_enabled_for_custom_domain is default-OFF (a domain
    # must opt in); resolve_*_enabled follows the operator's global default.
    #
    # The branch is chosen by SigninConfig.operator_host?, NOT by
    # custom_domain_request?
    # (ADR-024#operator-defaults-require-positive-classification): the
    # operator branch requires a
    # POSITIVE :canonical/:subdomain classification, so :invalid and nil take
    # the tenant-safe branch along with :custom. That is the one row in this
    # file where the auth gates deliberately DISAGREE with the identity
    # predicates above — those stay `== :custom`.
    describe 'gate polarity' do
      before do
        allow(OT).to receive(:conf).and_return({ 'site' => { 'authentication' => {} } })
      end

      DomainStrategyContract::CLASSIFICATIONS.each do |strategy|
        operator = DomainStrategyContract::OPERATOR.include?(strategy)

        it "signin_enabled? takes the #{operator ? 'operator' : 'custom-domain'} branch for #{strategy.inspect}" do
          controller = controller_for(strategy)
          allow(controller).to receive(:domain_signin_config).and_return(nil)
          allow(Onetime::CustomDomain::SigninConfig).to receive(:global_signin_enabled).and_return(true)

          expected_branch = operator ? :resolve_signin_enabled : :resolve_signin_enabled_for_custom_domain
          expect(Onetime::CustomDomain::SigninConfig).to receive(expected_branch).and_return(true)

          controller.send(:signin_enabled?)
        end

        it "signup_enabled? takes the #{operator ? 'operator' : 'custom-domain'} branch for #{strategy.inspect}" do
          controller = controller_for(strategy)
          allow(controller).to receive(:domain_signup_config).and_return(nil)
          allow(Onetime::CustomDomain::SignupConfig).to receive(:global_signup_enabled).and_return(true)

          expected_branch = operator ? :resolve_signup_enabled : :resolve_signup_enabled_for_custom_domain
          expect(Onetime::CustomDomain::SignupConfig).to receive(expected_branch).and_return(true)

          controller.send(:signup_enabled?)
        end
      end

      # ADR-024#operator-defaults-require-positive-classification, CLOSED.
      # This is the row the table exists for: the defect
      # was invisible unless :invalid was evaluated against both branches side
      # by side. Before the fix, a domain that never opted into sign-up
      # followed the OPERATOR's default while misclassified — a datastore blip
      # widening access on someone else's domain. This example is deliberately
      # kept (not deleted) with its expectation inverted, so that a
      # re-introduction of the `== :custom` branch selection reds HERE with the
      # history attached rather than passing silently.
      it ':invalid resolves the tenant-safe sign-up default, not the operator one' do
        controller = controller_for(:invalid)
        allow(controller).to receive(:domain_signup_config).and_return(nil)
        allow(Onetime::CustomDomain::SignupConfig).to receive(:global_signup_enabled).and_return(true)

        # No config + tenant-safe polarity => default-OFF, the same answer the
        # request would get if it had been classified :custom correctly.
        expect(controller.send(:signup_enabled?)).to be(false)
        expect(
          Onetime::CustomDomain::SignupConfig.resolve_signup_enabled_for_custom_domain(true, nil),
        ).to be(false)
      end

      # Sign-in has the same inverted-default risk and the same fix; pinned
      # explicitly so a partial revert (one gate only) cannot pass.
      it ':invalid resolves the tenant-safe sign-in default, not the operator one' do
        controller = controller_for(:invalid)
        allow(controller).to receive(:domain_signin_config).and_return(nil)
        allow(Onetime::CustomDomain::SigninConfig).to receive(:global_signin_enabled).and_return(true)

        expect(controller.send(:signin_enabled?)).to be(false)
        expect(
          Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_custom_domain(true, nil),
        ).to be(false)
      end

      # nil is the same failure with a different provenance: a request that
      # never passed through the middleware carries no classification at all.
      it 'nil is tenant-safe for both gates' do
        controller = controller_for(nil)
        allow(controller).to receive_messages(domain_signin_config: nil, domain_signup_config: nil)
        allow(Onetime::CustomDomain::SigninConfig).to receive(:global_signin_enabled).and_return(true)
        allow(Onetime::CustomDomain::SignupConfig).to receive(:global_signup_enabled).and_return(true)

        expect(controller.send(:signin_enabled?)).to be(false)
        expect(controller.send(:signup_enabled?)).to be(false)
      end
    end
  end

  # ---------------------------------------------------------------- rows 5-6
  describe 'Auth::RestrictTo' do
    # The 'sso' pin describes a tenant host reachable only via SSO. It is
    # skipped entirely for a misclassified host, so that host stops being
    # pinned to SSO for the duration of the blip.
    describe 'host pin' do
      before do
        allow(Onetime::CustomDomain::SsoConfig)
          .to receive(:sso_available_for_tenant_host?).and_return(true)
        allow(Onetime.auth_config).to receive(:restrict_to).and_return(nil)
      end

      DomainStrategyContract::CLASSIFICATIONS.each do |strategy|
        expected = strategy == :custom ? 'sso' : nil

        it "pins #{expected.inspect} for #{strategy.inspect}" do
          pinned = Auth::RestrictTo.global_restrict_to(env_for(strategy), 'domain_abc', nil)
          expect(pinned).to eq(expected)
        end
      end
    end

    describe 'custom_host: input to the availability half' do
      before do
        allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)
        allow(Onetime.auth_config).to receive(:restrict_to).and_return(nil)
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id).and_return(nil)
      end

      DomainStrategyContract::CLASSIFICATIONS.each do |strategy|
        expected = strategy == :custom

        it "passes custom_host: #{expected} for #{strategy.inspect}" do
          expect(Onetime::CustomDomain::SigninConfig)
            .to receive(:restriction_available_for_request?)
            .with(anything, anything, hash_including(custom_host: expected))
            .and_return(true)

          Auth::RestrictTo.resolution_for(env_for(strategy))
        end
      end
    end
  end

  # ---------------------------------------------------------------- row 7
  describe 'ConfigSerializer.tenant_domain?' do
    DomainStrategyContract::CLASSIFICATIONS.each do |strategy|
      expected = strategy == :custom

      it "answers #{expected} for #{strategy.inspect}" do
        answer = Core::Views::ConfigSerializer.tenant_domain?('domain_strategy' => strategy)
        expect(answer).to be(expected)
      end
    end
  end

  # ---------------------------------------------------------------- row 7b
  #
  # The DISPLAY-side twin of SigninConfig.operator_host?
  # (ADR-024#identity-predicates-are-not-auth-gates). It is
  # NOT the negation of tenant_domain? above: :invalid and nil are neither
  # operator hosts nor tenant hosts, and both predicates must answer false for
  # them — tenant-safe for auth, non-tenant for branding/routing.
  describe 'ConfigSerializer.operator_domain?' do
    DomainStrategyContract::CLASSIFICATIONS.each do |strategy|
      expected = DomainStrategyContract::OPERATOR.include?(strategy)

      it "answers #{expected} for #{strategy.inspect}" do
        answer = Core::Views::ConfigSerializer.operator_domain?('domain_strategy' => strategy)
        expect(answer).to be(expected)
      end
    end

    it 'delegates to SigninConfig.operator_host? — one owner of the classification list' do
      expect(Onetime::CustomDomain::SigninConfig)
        .to receive(:operator_host?).with(:canonical).and_return(true)

      Core::Views::ConfigSerializer.operator_domain?('domain_strategy' => :canonical)
    end

    it 'is never simultaneously true with tenant_domain?, and both are false for :invalid/nil' do
      DomainStrategyContract::CLASSIFICATIONS.each do |strategy|
        vars   = { 'domain_strategy' => strategy }
        tenant = Core::Views::ConfigSerializer.tenant_domain?(vars)
        opera  = Core::Views::ConfigSerializer.operator_domain?(vars)

        expect(tenant && opera).to be(false)
        expect([tenant, opera]).to eq([false, false]) if [:invalid, nil].include?(strategy)
      end
    end
  end

  # ---------------------------------------------------------------- row 10
  #
  # The API v1 stack compares stringified, not by Symbol. Pinned because the
  # two forms must agree: StrategyResult metadata carries Symbols, but this
  # consumer would silently answer false for 'custom' if it ever switched to
  # a strict `== :custom`.
  describe 'V1::Logic::Base#custom_domain?' do
    DomainStrategyContract::CLASSIFICATIONS.each do |strategy|
      expected = strategy == :custom

      it "answers #{expected} for #{strategy.inspect}" do
        logic                 = V1::Logic::Base.allocate
        logic.domain_strategy = strategy
        expect(logic.send(:custom_domain?)).to be(expected)
      end
    end

    it 'accepts the String form — metadata is not always a Symbol' do
      logic                 = V1::Logic::Base.allocate
      logic.domain_strategy = 'custom'
      expect(logic.send(:custom_domain?)).to be(true)
    end
  end

  # ---------------------------------------------------------- identity read
  #
  # THE READ ITSELF, NOT A STUB OF IT (#4157). Every fail-closed example above
  # and in the parity spec stubs the CustomDomain finder to raise — which is
  # exactly what hid this: the sign-in gates called
  # CustomDomain.load_by_display_domain, whose own body rescues
  # Redis::BaseError AND a blanket StandardError and returns nil ("intentional
  # fail-open behavior for the lookup layer", and correct for its ~15 CLI,
  # operations and serializer callers). So in production a blip produced nil,
  # not a raise: the gate read it as "this host has no SigninConfig" and fell
  # through to the operator's global default on a tenant host. The rescue those
  # gates carry was dead code, and every spec that stubbed the finder to raise
  # jumped over the swallow.
  #
  # These examples therefore stub ONLY the datastore seam (display_domain_index)
  # and let the real finder run, so the swallow-vs-propagate boundary is what is
  # under test. If someone repoints an identity read back at the fail-open
  # helper, these red and the stubbed examples do not.
  describe 'the sign-in identity read propagates datastore failures' do
    let(:blip) { Redis::BaseError.new('connection reset') }

    let(:failing_index) do
      instance_double(Familia::HashKey).tap do |index|
        allow(index).to receive(:get).and_raise(blip)
      end
    end

    let(:controller_class) do
      Class.new do
        include Core::Controllers::Base

        def initialize(env)
          @req = Struct.new(:env).new(env)
        end
      end
    end

    before do
      allow(Onetime::CustomDomain).to receive(:display_domain_index).and_return(failing_index)
      allow(OT).to receive(:le)
      allow(Auth::Logging).to receive(:log_auth_event)
    end

    it 'raises out of CustomDomain.from_display_domain rather than answering nil' do
      expect { Onetime::CustomDomain.from_display_domain('tenant.example.com') }
        .to raise_error(Redis::BaseError)
    end

    it 'still swallows in load_by_display_domain — its other callers depend on that' do
      expect(Onetime::CustomDomain.load_by_display_domain('tenant.example.com')).to be_nil
    end

    DomainStrategyContract::CLASSIFICATIONS.each do |strategy|
      operator = DomainStrategyContract::OPERATOR.include?(strategy)

      if operator
        it "resolves custom_domain_id to nil on #{strategy.inspect} — no per-domain policy to lose" do
          expect(controller_class.new(env_for(strategy)).send(:custom_domain_id)).to be_nil
        end
      else
        it "raises SigninPolicyUnavailable from custom_domain_id on #{strategy.inspect}" do
          expect { controller_class.new(env_for(strategy)).send(:custom_domain_id) }
            .to raise_error(Onetime::SigninPolicyUnavailable)
        end
      end
    end

    # The row this exists for: the widen was silent BECAUSE the gate got a
    # plausible nil. signin_enabled? must not answer at all here.
    it 'does not let signin_enabled? answer from the operator global default on :invalid' do
      controller = controller_class.new(env_for(:invalid))
      allow(OT).to receive(:conf).and_return({ 'site' => { 'authentication' => {} } })
      allow(Onetime::CustomDomain::SigninConfig).to receive(:global_signin_enabled).and_return(true)

      expect { controller.send(:signin_enabled?) }
        .to raise_error(Onetime::SigninPolicyUnavailable)
    end

    # Auth::RestrictTo reads the same identity through its own helper, so it
    # had the same dead rescue: resolution_for's comment names the CustomDomain
    # lookup as one of the three reads it guards, and it was the one that could
    # not reach it.
    it 'fails the restrict_to gate closed instead of inheriting the global restriction' do
      allow(Onetime.auth_config).to receive(:restrict_to).and_return('password')
      allow(Onetime::CustomDomain::SigninConfig)
        .to receive(:global_restriction_available?).and_return(true)

      expect { Auth::RestrictTo.resolution_for(env_for(:custom)) }
        .to raise_error(Onetime::SigninPolicyUnavailable)
    end
  end

  # ------------------------------------------------------- host normalization
  #
  # A mixed-case Host is the same widen by a different route: the index is
  # keyed on the downcased display_domain, so an un-normalized lookup misses,
  # reads as "no tenant config", and hands a tenant host the operator default.
  # load_by_display_domain always downcased; from_display_domain did not, which
  # left it latent on both the sign-in and sign-up policy paths once they share
  # this finder.
  describe 'CustomDomain.from_display_domain host normalization' do
    let(:index) { instance_double(Familia::HashKey) }

    before do
      allow(Onetime::CustomDomain).to receive(:display_domain_index).and_return(index)
      allow(index).to receive(:get).and_return(nil)
      allow(index).to receive(:get).with('tenant.example.com').and_return('domain-1')
      allow(Onetime::CustomDomain).to receive(:find_by_identifier)
        .with('domain-1').and_return(:the_record)
    end

    ['tenant.example.com', 'Tenant.Example.com', 'TENANT.EXAMPLE.COM'].each do |host|
      it "resolves #{host.inspect} to the indexed record" do
        expect(Onetime::CustomDomain.from_display_domain(host)).to be(:the_record)
      end
    end

    it 'returns nil for a blank host without touching the index' do
      expect(Onetime::CustomDomain.from_display_domain(nil)).to be_nil
      expect(Onetime::CustomDomain.from_display_domain('')).to be_nil
      expect(index).not_to have_received(:get)
    end
  end

  # ---------------------------------------------------------------- invariant
  #
  # Guards the property the whole carve-out rests on: a datastore failure can
  # never MANUFACTURE an operator classification. If someone adds a datastore
  # read to choose_strategy ahead of the exact canonical arm, a blip would
  # start withdrawing :canonical too, and canonical sign-in would go dark with
  # everything else.
  describe 'operator classifications under a datastore failure' do
    before do
      allow(Onetime::CustomDomain)
        .to receive(:from_display_domain)
        .and_raise(Redis::BaseError, 'datastore unavailable')
    end

    it 'still classifies the canonical host :canonical when the datastore is down' do
      strategy = Onetime::Middleware::DomainStrategy::Chooserator
                 .choose_strategy('example.com', ['example.com'])
      expect(strategy).to eq(:canonical)
    end

    # NOT :subdomain — the sweeps run AFTER known_custom_domain? and the
    # rescue wraps the whole chain, so a raise aborts before reaching them.
    # Subdomain hosts fail closed alongside the custom domains; canonical
    # sign-in (above) stays up. This is the asymmetry that remained
    # unresolved — no ADR entry covers it — before this spec existed.
    it 'WITHDRAWS :subdomain when the datastore is down — it does not fall through' do
      strategy = Onetime::Middleware::DomainStrategy::Chooserator
                 .choose_strategy('api.example.com', ['example.com'])
      expect(strategy).to be_nil
    end

    it 'classifies a real custom domain nil (→ :invalid), never :subdomain' do
      strategy = Onetime::Middleware::DomainStrategy::Chooserator
                 .choose_strategy('tenant.example.com', ['other.example.org'])
      expect(strategy).to be_nil,
        'the rescue must abort the chain, not fall through into the subdomain sweep'
    end
  end
end
