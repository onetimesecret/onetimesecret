# apps/api/v2/spec/logic/secrets/base_secret_action_spec.rb
#
# frozen_string_literal: true

# ============================================================================
# Config Path Bug Tests (TDD Red Phase)
#
# These tests demonstrate that process_ttl reads secret_options from the
# WRONG config path. It does:
#
#   OT.conf.fetch('secret_options', { hardcoded fallback })
#
# But secret_options is nested under 'site' in config. The correct path
# (used by validate_passphrase in the same file) is:
#
#   OT.conf.dig('site', 'secret_options')
#
# As a result, process_ttl ALWAYS uses the hardcoded fallback values:
#   default_ttl: 604800 (7 days)
#   ttl_options: [60, 3600, 86400, 604800]
#
# Instead of the test config values (spec/config.test.yaml):
#   default_ttl: 43200 (12 hours)
#   ttl_options: [1800, 43200, 604800]
#
# These tests should FAIL against the current code and PASS after the fix.
# ============================================================================

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative File.join(Onetime::HOME, 'spec', 'support', 'model_test_helper.rb')

RSpec.describe 'V2 BaseSecretAction config path bug' do
  using Familia::Refinements::TimeLiterals

  # Subclass that implements the required abstract method
  class V2ConfigTestAction < V2::Logic::Secrets::BaseSecretAction
    def process_secret
      @kind = :test
      @secret_value = 'test_secret'
    end
  end

  # Stub organization_instances with a non-empty array so CreateDefaultWorkspace
  # sees the customer already has an org and skips creation (these tests are
  # about TTL config, not workspace creation).
  let(:customer) {
    double('Customer',
      anonymous?: false,
      custid: 'cust123',
      objid: 'obj123',
      planid: 'anonymous',
      email: 'cust123@example.com',
      organization_instances: [:existing_org])
  }

  let(:session) {
    double('Session',
      anonymous?: false,
      custid: 'cust123',
      identifier: 'sess123')
  }

  # V2 Logic::Base takes a strategy_result, not raw session/customer
  let(:strategy_result) {
    double('StrategyResult',
      session: session,
      user: customer,
      metadata: { organization_context: {} })
  }

  # V2 uses nested params: params['secret'] contains the secret fields
  let(:base_params) {
    {
      'secret' => {
        'recipient'    => [],
        'share_domain' => '',
      },
    }
  }

  subject { V2ConfigTestAction.new(strategy_result, base_params) }

  before(:all) do
    OT.boot!(:test)
  end

  before do
    allow(Truemail).to receive(:validate).and_return(
      double('Validator', result: double('Result', valid?: true), as_json: '{}'),
    )
  end

  describe '#process_ttl config path' do
    it 'reads default_ttl from site.secret_options in config (43200), not the hardcoded fallback (604800)' do
      # Verify the config actually has the value we expect at the correct path
      configured_default_ttl = OT.conf.dig('site', 'secret_options', 'default_ttl')
      expect(configured_default_ttl).to eq(43200), "Precondition: config.test.yaml should define site.secret_options.default_ttl as 43200"

      # Now test that process_ttl actually uses that config value when no TTL is provided
      subject.instance_variable_set(:@payload, {})
      subject.send(:process_ttl)

      expect(subject.ttl).to eq(43200),
        "Expected default_ttl=43200 from config, got #{subject.ttl}. " \
        "Bug: process_ttl reads OT.conf.fetch('secret_options') (root level) " \
        "instead of OT.conf.dig('site', 'secret_options')"
    end

    it 'reads ttl_options from site.secret_options in config, not the hardcoded fallback' do
      # The test config defines: ttl_options: '1800 43200 604800'
      # After OT::Config.after_load parses it, this becomes [1800, 43200, 604800]
      #
      # The hardcoded V2 fallback is [60, 3600, 86400, 604800]
      # So the arrays differ in both values and length.
      configured_options = OT.conf.dig('site', 'secret_options', 'ttl_options')
      expect(configured_options).to be_an(Array), "Precondition: after_load should parse ttl_options string into an array"
      expect(configured_options).to include(43200), "Precondition: ttl_options should include 43200"

      # The real differentiator: config min_ttl is 1800, but V2 hardcoded
      # fallback min is 60 (1.minute). A TTL of 120 (2 minutes) should be
      # clamped UP to 1800 by config, but the hardcoded fallback would allow
      # it through (since 120 > 60).
      subject.instance_variable_set(:@payload, { 'ttl' => '120' })
      subject.send(:process_ttl)

      expect(subject.ttl).to eq(1800),
        "Expected TTL=120 to be clamped to config min_ttl=1800, " \
        "got #{subject.ttl}. Bug: hardcoded fallback has min_ttl=60, " \
        "so 120 passes through unclamped."
    end

    it 'uses config default_ttl (43200) when TTL param is nil' do
      subject.instance_variable_set(:@payload, { 'ttl' => nil })
      subject.send(:process_ttl)

      expect(subject.ttl).to eq(43200),
        "Expected nil TTL to default to config's 43200, got #{subject.ttl}. " \
        "Bug: falls through to hardcoded 604800 because it reads from wrong config path."
    end

    it 'uses config default_ttl (43200) when TTL key is absent from payload' do
      subject.instance_variable_set(:@payload, {})
      subject.send(:process_ttl)

      expect(subject.ttl).to eq(43200),
        "Expected absent TTL to default to config's 43200, got #{subject.ttl}. " \
        "Bug: falls through to hardcoded 604800 because it reads from wrong config path."
    end

    it 'enforces config min_ttl (1800) not hardcoded min_ttl (60)' do
      # V2 hardcoded fallback: ttl_options.min = 60 (1.minute)
      # Config value: ttl_options.min = 1800 (30 minutes)
      #
      # A TTL of 300 (5 minutes) is above the hardcoded min but below config min.
      subject.instance_variable_set(:@payload, { 'ttl' => '300' })
      subject.send(:process_ttl)

      expect(subject.ttl).to eq(1800),
        "Expected TTL=300 to be clamped to config min=1800, got #{subject.ttl}. " \
        "Bug: hardcoded fallback min is 60, so values between 60-1800 pass through."
    end
  end

  # ============================================================================
  # i18n error_key on validate_domain_permissions Forbidden raises
  #
  # validate_domain_permissions raises Onetime::Forbidden in three distinct
  # branches; each carries its own error_key so the HTTP edge can localize.
  # The pre-set English message is preserved as the resolver's I18n.t default,
  # so legacy message-regex specs keep passing if the locale key is missing.
  # ============================================================================
  describe '#validate_domain_permissions error_key plumbing' do
    let(:share_domain) { 'secrets.acme.com' }
    let(:authenticated_customer) do
      double('Customer',
        anonymous?: false,
        custid: 'cust123',
        objid: 'obj123',
        planid: 'anonymous',
        email: 'cust123@example.com',
        organization_instances: [:existing_org])
    end
    let(:anonymous_customer) do
      double('Customer',
        anonymous?: true,
        custid: nil,
        objid: nil,
        planid: 'anonymous',
        email: nil,
        organization_instances: [])
    end

    # Stand-in for CustomDomain. owner? and allow_public_homepage? are the
    # only methods validate_domain_permissions touches on the record.
    def build_domain_record(owner: false, allow_public_homepage: false)
      double('CustomDomain', owner?: owner, allow_public_homepage?: allow_public_homepage)
    end

    # Build a subject seeded with @cust and @share_domain so the helper
    # method can be called directly without process_params side effects.
    def build_subject(cust:, custom_domain: false)
      action = V2ConfigTestAction.new(strategy_result, base_params)
      action.instance_variable_set(:@cust, cust)
      action.instance_variable_set(:@share_domain, share_domain)
      allow(action).to receive(:custom_domain?).and_return(custom_domain)
      # secret_logger is noisy; the warn calls aren't under test here.
      allow(action).to receive(:secret_logger).and_return(double('Logger').as_null_object)
      action
    end

    context 'authenticated non-owner branch (line ~445)' do
      let(:domain_record) { build_domain_record(owner: false) }
      subject { build_subject(cust: authenticated_customer, custom_domain: false) }

      it 'raises Onetime::Forbidden' do
        expect { subject.send(:validate_domain_permissions, domain_record) }
          .to raise_error(Onetime::Forbidden)
      end

      it 'tags the error with the authenticated_non_owner i18n key' do
        expect { subject.send(:validate_domain_permissions, domain_record) }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.error_key)
              .to eq('api.secrets.errors.domain_permission_authenticated_non_owner')
          end
      end

      it 'preserves the interpolated legacy English message as the fallback' do
        expect { subject.send(:validate_domain_permissions, domain_record) }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.message).to eq("You do not have permission to use domain: #{share_domain}")
          end
      end

      it 'passes share_domain through args for i18n %{domain} interpolation' do
        expect { subject.send(:validate_domain_permissions, domain_record) }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.args).to eq(domain: share_domain)
          end
      end

      it 'serializes error_key into to_h for the HTTP response body' do
        expect { subject.send(:validate_domain_permissions, domain_record) }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.to_h).to include(
              error: "You do not have permission to use domain: #{share_domain}",
              error_type: 'Forbidden',
              error_key: 'api.secrets.errors.domain_permission_authenticated_non_owner',
            )
          end
      end
    end

    context 'anonymous on custom domain with public sharing disabled (line ~459)' do
      let(:domain_record) { build_domain_record(owner: false, allow_public_homepage: false) }
      subject { build_subject(cust: anonymous_customer, custom_domain: true) }

      it 'raises Onetime::Forbidden' do
        expect { subject.send(:validate_domain_permissions, domain_record) }
          .to raise_error(Onetime::Forbidden)
      end

      it 'tags the error with the public_sharing_disabled i18n key' do
        expect { subject.send(:validate_domain_permissions, domain_record) }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.error_key)
              .to eq('api.secrets.errors.domain_public_sharing_disabled')
          end
      end

      it 'preserves the interpolated legacy English message as the fallback' do
        expect { subject.send(:validate_domain_permissions, domain_record) }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.message).to eq("Public sharing disabled for domain: #{share_domain}")
          end
      end

      it 'passes share_domain through args for i18n %{domain} interpolation' do
        expect { subject.send(:validate_domain_permissions, domain_record) }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.args).to eq(domain: share_domain)
          end
      end

      it 'serializes error_key into to_h for the HTTP response body' do
        expect { subject.send(:validate_domain_permissions, domain_record) }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.to_h).to include(
              error: "Public sharing disabled for domain: #{share_domain}",
              error_type: 'Forbidden',
              error_key: 'api.secrets.errors.domain_public_sharing_disabled',
            )
          end
      end
    end

    context 'anonymous on canonical attempting cross-domain (line ~470)' do
      let(:domain_record) { build_domain_record(owner: false, allow_public_homepage: true) }
      subject { build_subject(cust: anonymous_customer, custom_domain: false) }

      it 'raises Onetime::Forbidden' do
        expect { subject.send(:validate_domain_permissions, domain_record) }
          .to raise_error(Onetime::Forbidden)
      end

      it 'tags the error with the anonymous_cross_domain i18n key' do
        expect { subject.send(:validate_domain_permissions, domain_record) }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.error_key)
              .to eq('api.secrets.errors.domain_permission_anonymous_cross_domain')
          end
      end

      it 'preserves the interpolated legacy English message as the fallback' do
        expect { subject.send(:validate_domain_permissions, domain_record) }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.message).to eq("You do not have permission to use domain: #{share_domain}")
          end
      end

      it 'passes share_domain through args for i18n %{domain} interpolation' do
        expect { subject.send(:validate_domain_permissions, domain_record) }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.args).to eq(domain: share_domain)
          end
      end

      it 'serializes error_key into to_h for the HTTP response body' do
        expect { subject.send(:validate_domain_permissions, domain_record) }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.to_h).to include(
              error: "You do not have permission to use domain: #{share_domain}",
              error_type: 'Forbidden',
              error_key: 'api.secrets.errors.domain_permission_anonymous_cross_domain',
            )
          end
      end

      it 'uses a distinct error_key from the authenticated non-owner branch despite identical English text' do
        # The two raises render the same English message but represent
        # different policy decisions (auth vs anon cross-domain). Distinct
        # keys let locale entries and ops dashboards tell them apart.
        expect { subject.send(:validate_domain_permissions, domain_record) }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.error_key)
              .not_to eq('api.secrets.errors.domain_permission_authenticated_non_owner')
          end
      end
    end

    context 'domain owner (no raise)' do
      let(:domain_record) { build_domain_record(owner: true) }
      subject { build_subject(cust: authenticated_customer, custom_domain: false) }

      it 'returns without raising' do
        expect { subject.send(:validate_domain_permissions, domain_record) }.not_to raise_error
      end
    end
  end

  # ============================================================================
  # determine_share_domain — domain selection fix
  #
  # The bug: when browsing on a custom domain (Host header = custom domain) and
  # selecting a DIFFERENT org domain from the Domain Context dropdown, the old
  # code always returned display_domain (the Host header's domain), ignoring
  # the user's explicit share_domain selection.
  #
  # Old code:
  #   return display_domain if custom_domain?
  #   share_domain
  #
  # Fixed code:
  #   return share_domain if share_domain
  #   display_domain if custom_domain?
  # ============================================================================
  describe '#determine_share_domain' do
    # Build a subject with explicit control over share_domain, display_domain,
    # custom_domain?, and anonymity — the inputs to determine_share_domain.
    #
    # anonymous_user? resolves via cust (cust.nil? || cust.anonymous?). The
    # default strategy_result.user is a non-anonymous customer; pass
    # anonymous: true to swap in an anonymous customer and exercise the guest
    # guard added for issue #3311.
    def build_domain_subject(share_domain:, display_domain:, custom_domain:, anonymous: false)
      action = V2ConfigTestAction.new(strategy_result, base_params)
      action.instance_variable_set(:@share_domain, share_domain)
      action.instance_variable_set(:@display_domain, display_domain)
      if anonymous
        action.instance_variable_set(:@cust,
          double('AnonymousCustomer', anonymous?: true, custid: nil, objid: nil))
      end
      allow(action).to receive(:custom_domain?).and_return(custom_domain)
      allow(action).to receive(:secret_logger).and_return(double('Logger').as_null_object)
      action
    end

    context 'user on custom domain, explicit share_domain set to a different domain' do
      subject do
        build_domain_subject(
          share_domain: 'secrets.acme.com',
          display_domain: 'local-secrets.afb.pet',
          custom_domain: true,
        )
      end

      it 'returns the explicitly selected share_domain, not the Host header domain' do
        result = subject.send(:determine_share_domain)
        expect(result).to eq('secrets.acme.com')
      end
    end

    context 'user on custom domain, no explicit share_domain (nil)' do
      subject do
        build_domain_subject(
          share_domain: nil,
          display_domain: 'local-secrets.afb.pet',
          custom_domain: true,
        )
      end

      it 'falls back to the display_domain from the Host header' do
        result = subject.send(:determine_share_domain)
        expect(result).to eq('local-secrets.afb.pet')
      end
    end

    context 'user on canonical domain, explicit share_domain set' do
      subject do
        build_domain_subject(
          share_domain: 'secrets.acme.com',
          display_domain: 'onetimesecret.com',
          custom_domain: false,
        )
      end

      it 'returns the explicitly selected share_domain' do
        result = subject.send(:determine_share_domain)
        expect(result).to eq('secrets.acme.com')
      end
    end

    context 'user on canonical domain, no share_domain' do
      subject do
        build_domain_subject(
          share_domain: nil,
          display_domain: 'onetimesecret.com',
          custom_domain: false,
        )
      end

      it 'returns nil (no custom domain context, no explicit selection)' do
        result = subject.send(:determine_share_domain)
        expect(result).to be_nil
      end
    end

    context 'user on custom domain, share_domain matches display_domain' do
      subject do
        build_domain_subject(
          share_domain: 'local-secrets.afb.pet',
          display_domain: 'local-secrets.afb.pet',
          custom_domain: true,
        )
      end

      it 'returns share_domain (explicit selection takes precedence even when same)' do
        result = subject.send(:determine_share_domain)
        expect(result).to eq('local-secrets.afb.pet')
      end
    end

    # --------------------------------------------------------------------------
    # Guest (anonymous) guard — issue #3311
    #
    # determine_share_domain runs before any auth check, and process_share_domain
    # populates @share_domain straight from the POST body with no auth gate. The
    # explicit share_domain override is the authenticated Domain Context selector;
    # a guest has no legitimate source for it. So a guest already browsing one
    # custom domain could otherwise smuggle a *different* public custom domain in
    # via the POST body and have their secret pinned there. Anonymous users on a
    # custom domain must always resolve to the Host-header (display) domain,
    # regardless of what the POST body claims.
    #
    # The fixtures above all use the default non-anonymous customer, so they
    # double as the "authenticated user still selects via share_domain" no-
    # regression checks. The contexts below pin the guest behaviour.
    # --------------------------------------------------------------------------
    context 'anonymous guest on custom domain, explicit share_domain in POST body' do
      subject do
        build_domain_subject(
          share_domain: 'secrets.acme.com',
          display_domain: 'local-secrets.afb.pet',
          custom_domain: true,
          anonymous: true,
        )
      end

      it 'ignores the POST-body share_domain and returns the Host header domain' do
        result = subject.send(:determine_share_domain)
        expect(result).to eq('local-secrets.afb.pet')
      end
    end

    context 'anonymous guest on custom domain, no explicit share_domain' do
      subject do
        build_domain_subject(
          share_domain: nil,
          display_domain: 'local-secrets.afb.pet',
          custom_domain: true,
          anonymous: true,
        )
      end

      it 'returns the Host header domain' do
        result = subject.send(:determine_share_domain)
        expect(result).to eq('local-secrets.afb.pet')
      end
    end

    context 'anonymous guest on canonical domain, explicit share_domain in POST body' do
      subject do
        build_domain_subject(
          share_domain: 'secrets.acme.com',
          display_domain: 'onetimesecret.com',
          custom_domain: false,
          anonymous: true,
        )
      end

      # The guard is scoped to custom_domain?: on the canonical domain
      # determine_share_domain still surfaces the posted share_domain. The
      # cross-domain rejection for guests happens downstream in
      # validate_domain_permissions (the anonymous_cross_domain branch), which
      # is covered separately above — not in this selection step.
      it 'returns the posted share_domain (cross-domain rejection is enforced later)' do
        result = subject.send(:determine_share_domain)
        expect(result).to eq('secrets.acme.com')
      end
    end
  end

  # ============================================================================
  # validate_share_domain integration — verifies that determine_share_domain's
  # return value flows through to validate_domain_access correctly.
  # ============================================================================
  describe '#validate_share_domain integration' do
    # Domain double that passes all permission and verification checks.
    def build_passing_domain_record(owner: true)
      double('CustomDomain',
        owner?: owner,
        allow_public_homepage?: true,
        verified: 'true')
    end

    def build_integration_subject(cust:, share_domain:, display_domain:, custom_domain:)
      action = V2ConfigTestAction.new(strategy_result, base_params)
      action.instance_variable_set(:@cust, cust)
      action.instance_variable_set(:@share_domain, share_domain)
      action.instance_variable_set(:@display_domain, display_domain)
      allow(action).to receive(:custom_domain?).and_return(custom_domain)
      allow(action).to receive(:secret_logger).and_return(double('Logger').as_null_object)
      action
    end

    let(:authenticated_member) do
      double('Customer',
        anonymous?: false,
        custid: 'member1',
        objid: 'obj_member1',
        planid: 'identity',
        email: 'member@acme.com',
        organization_instances: [:existing_org])
    end

    let(:anonymous_visitor) do
      double('Customer',
        anonymous?: true,
        custid: nil,
        objid: nil,
        planid: 'anonymous',
        email: nil,
        organization_instances: [])
    end

    context 'authenticated domain owner on custom domain, selects a different owned domain' do
      let(:selected_domain) { 'secrets.acme.com' }
      let(:host_domain)     { 'local-secrets.afb.pet' }
      let(:domain_record)   { build_passing_domain_record(owner: true) }

      subject do
        build_integration_subject(
          cust: authenticated_member,
          share_domain: selected_domain,
          display_domain: host_domain,
          custom_domain: true,
        )
      end

      before do
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .with(selected_domain).and_return(domain_record)
      end

      it 'uses the explicitly selected domain, not the Host header domain' do
        expect { subject.send(:validate_share_domain) }.not_to raise_error
        expect(subject.share_domain).to eq(selected_domain)
      end

      it 'looks up the selected domain record, not the Host header domain' do
        subject.send(:validate_share_domain)
        expect(Onetime::CustomDomain).to have_received(:from_display_domain).with(selected_domain)
      end
    end

    context 'authenticated non-owner on custom domain, selects a domain they do not own' do
      let(:selected_domain) { 'secrets.other.com' }
      let(:host_domain)     { 'local-secrets.afb.pet' }
      let(:domain_record) do
        double('CustomDomain',
          owner?: false,
          allow_public_homepage?: false,
          verified: 'true')
      end

      subject do
        build_integration_subject(
          cust: authenticated_member,
          share_domain: selected_domain,
          display_domain: host_domain,
          custom_domain: true,
        )
      end

      before do
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .with(selected_domain).and_return(domain_record)
      end

      it 'raises Forbidden for the explicitly selected domain' do
        expect { subject.send(:validate_share_domain) }
          .to raise_error(Onetime::Forbidden)
      end
    end

    context 'authenticated domain owner on custom domain, no explicit selection' do
      let(:host_domain)   { 'local-secrets.afb.pet' }
      let(:domain_record) { build_passing_domain_record(owner: true) }

      subject do
        build_integration_subject(
          cust: authenticated_member,
          share_domain: nil,
          display_domain: host_domain,
          custom_domain: true,
        )
      end

      before do
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .with(host_domain).and_return(domain_record)
      end

      it 'falls back to the Host header domain' do
        expect { subject.send(:validate_share_domain) }.not_to raise_error
        expect(subject.share_domain).to eq(host_domain)
      end

      it 'looks up the Host header domain record' do
        subject.send(:validate_share_domain)
        expect(Onetime::CustomDomain).to have_received(:from_display_domain).with(host_domain)
      end
    end

    context 'anonymous user on custom domain, no explicit selection' do
      let(:host_domain)   { 'local-secrets.afb.pet' }
      let(:domain_record) do
        double('CustomDomain',
          owner?: false,
          allow_public_homepage?: true,
          verified: 'true')
      end

      subject do
        build_integration_subject(
          cust: anonymous_visitor,
          share_domain: nil,
          display_domain: host_domain,
          custom_domain: true,
        )
      end

      before do
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .with(host_domain).and_return(domain_record)
      end

      it 'falls back to the Host header domain and passes when public homepage is enabled' do
        expect { subject.send(:validate_share_domain) }.not_to raise_error
        expect(subject.share_domain).to eq(host_domain)
      end
    end

    # End-to-end regression for issue #3311: a guest browsing one custom domain
    # POSTs a share_domain pointing at a *different* public custom domain. Before
    # the anonymous_user? guard, determine_share_domain handed that smuggled
    # value straight to validate_domain_access, pinning the secret onto someone
    # else's branded domain. The guard must keep the secret on the Host domain
    # and never even look the smuggled domain up.
    context 'anonymous guest on custom domain, smuggles a different custom domain via share_domain' do
      let(:host_domain)     { 'local-secrets.afb.pet' }
      let(:smuggled_domain) { 'secrets.acme.com' }
      let(:host_record) do
        double('CustomDomain',
          owner?: false,
          allow_public_homepage?: true,
          verified: 'true')
      end

      subject do
        build_integration_subject(
          cust: anonymous_visitor,
          share_domain: smuggled_domain,
          display_domain: host_domain,
          custom_domain: true,
        )
      end

      before do
        # Default any lookup to nil so a smuggled-domain lookup would surface as
        # an "Unknown domain" failure rather than silently passing.
        allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .with(host_domain).and_return(host_record)
      end

      it 'pins the secret to the Host header domain, ignoring the smuggled share_domain' do
        expect { subject.send(:validate_share_domain) }.not_to raise_error
        expect(subject.share_domain).to eq(host_domain)
      end

      it 'never looks up the smuggled domain record' do
        subject.send(:validate_share_domain)
        expect(Onetime::CustomDomain).to have_received(:from_display_domain).with(host_domain)
        expect(Onetime::CustomDomain).not_to have_received(:from_display_domain).with(smuggled_domain)
      end
    end
  end
end
