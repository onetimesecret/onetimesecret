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
  # process_share_domain — ingestion boundary
  #
  # The #3311 root-cause fix lives here: an anonymous request must never populate
  # @share_domain from the POST body. The explicit share_domain is the
  # authenticated Domain Context selector, so refusing it at ingestion keeps
  # untrusted input out of the trusted instance variable entirely — rather than
  # relying on validate_share_domain to scrub a smuggled value back out later.
  #
  # The remaining contexts pin the method's existing validation contract (empty,
  # invalid, and canonical/default domains all leave @share_domain nil), which
  # previously had no direct coverage despite now gating a security boundary.
  # ============================================================================
  describe '#process_share_domain' do
    # Build a subject and drive process_share_domain directly with a chosen
    # payload value and anonymity. anonymous_user? resolves via cust.
    def build_ingest_subject(payload_share_domain:, anonymous:)
      action = V2ConfigTestAction.new(strategy_result, base_params)
      action.instance_variable_set(:@payload, { 'share_domain' => payload_share_domain })
      if anonymous
        action.instance_variable_set(:@cust,
          double('AnonymousCustomer', anonymous?: true, custid: nil, objid: nil))
      end
      allow(action).to receive(:secret_logger).and_return(double('Logger').as_null_object)
      action
    end

    context 'anonymous request with a valid, non-default custom domain in the payload' do
      subject { build_ingest_subject(payload_share_domain: 'secrets.acme.com', anonymous: true) }

      before do
        # The domain would otherwise sail through the validity/default checks;
        # the anonymous guard must short-circuit before they are ever consulted.
        allow(Onetime::CustomDomain).to receive(:valid?).and_return(true)
        allow(Onetime::CustomDomain).to receive(:default_domain?).and_return(false)
      end

      it 'does not populate @share_domain from the guest payload' do
        subject.send(:process_share_domain)
        expect(subject.share_domain).to be_nil
      end

      it 'short-circuits before consulting CustomDomain.valid?' do
        subject.send(:process_share_domain)
        expect(Onetime::CustomDomain).not_to have_received(:valid?)
      end
    end

    context 'authenticated request with a valid, non-default custom domain in the payload' do
      subject { build_ingest_subject(payload_share_domain: 'secrets.acme.com', anonymous: false) }

      before do
        allow(Onetime::CustomDomain).to receive(:valid?).with('secrets.acme.com').and_return(true)
        allow(Onetime::CustomDomain).to receive(:default_domain?).with('secrets.acme.com').and_return(false)
      end

      it 'still ingests the explicitly selected domain (no regression for the Domain Context selector)' do
        subject.send(:process_share_domain)
        expect(subject.share_domain).to eq('secrets.acme.com')
      end
    end

    context 'authenticated request with an empty share_domain in the payload' do
      subject { build_ingest_subject(payload_share_domain: '', anonymous: false) }

      it 'leaves @share_domain nil' do
        subject.send(:process_share_domain)
        expect(subject.share_domain).to be_nil
      end
    end

    context 'authenticated request with a malformed share_domain' do
      subject { build_ingest_subject(payload_share_domain: 'not a domain', anonymous: false) }

      before do
        allow(Onetime::CustomDomain).to receive(:valid?).and_return(false)
      end

      it 'rejects the invalid domain and leaves @share_domain nil' do
        subject.send(:process_share_domain)
        expect(subject.share_domain).to be_nil
      end
    end

    context "authenticated request whose share_domain is the site's canonical domain" do
      subject { build_ingest_subject(payload_share_domain: 'onetimesecret.com', anonymous: false) }

      before do
        allow(Onetime::CustomDomain).to receive(:valid?).and_return(true)
        allow(Onetime::CustomDomain).to receive(:default_domain?).and_return(true)
      end

      it 'skips the canonical/default domain and leaves @share_domain nil' do
        subject.send(:process_share_domain)
        expect(subject.share_domain).to be_nil
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
    # Guest (anonymous) second-layer guard — issue #3311
    #
    # process_share_domain (tested above) is the primary fix: it stops a guest
    # value from ever reaching @share_domain. These contexts deliberately set
    # @share_domain directly to exercise determine_share_domain's independent
    # second layer — even if some future writer were to set @share_domain for an
    # anonymous request, the domain-selection authority still pins a custom-domain
    # guest to the Host header and ignores the smuggled value.
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

    # End-to-end regression for issue #3311 (second layer). This seeds
    # @share_domain directly — as if a smuggled value had reached it despite the
    # ingestion guard — for a guest browsing one custom domain with the value
    # pointing at a *different* public custom domain. determine_share_domain must
    # keep the secret on the Host domain and validate_domain_access must never
    # even look the smuggled domain up.
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

  # ============================================================================
  # Full-payload end-to-end regression (issue #3311)
  #
  # Unlike the focused specs above (which seed instance variables), this drives
  # the real entry points with a real params payload: an anonymous guest, on a
  # custom domain, POSTs a secret whose body smuggles a share_domain for a
  # *different* public custom domain. process_params (real ingestion, run during
  # initialize) must drop the smuggled value, and raise_concerns (the real
  # validation pipeline) must resolve the share domain to the Host header and
  # never look the smuggled domain up. custom_domain? and display_domain are the
  # genuine values derived from the StrategyResult metadata here — only the
  # external CustomDomain lookup and the logger are stubbed.
  # ============================================================================
  describe 'full-payload end-to-end (anonymous guest smuggling share_domain)' do
    let(:host_domain)     { 'local-secrets.afb.pet' }
    let(:smuggled_domain) { 'secrets.acme.com' }

    let(:e2e_session) do
      double('Session', anonymous?: true, custid: nil, identifier: 'anon-sess')
    end

    # A genuinely anonymous StrategyResult: user is nil, so anonymous_user? is
    # true from construction onward (process_params runs during initialize).
    let(:e2e_strategy_result) do
      double('StrategyResult',
        session: e2e_session,
        user: nil,
        auth_method: :noauth,
        metadata: {
          organization_context: {},
          domain_strategy: 'custom',
          display_domain: host_domain,
        })
    end

    # Real nested payload, exactly as a guest POST would arrive, with the
    # smuggled share_domain riding along in the secret hash.
    let(:e2e_params) do
      {
        'secret' => {
          'secret'       => 'top secret value',
          'share_domain' => smuggled_domain,
          'ttl'          => '3600',
          'recipient'    => [],
        },
      }
    end

    let(:host_record) do
      double('CustomDomain', owner?: false, allow_public_homepage?: true, verified: 'true')
    end

    subject do
      action = V2ConfigTestAction.new(e2e_strategy_result, e2e_params)
      allow(action).to receive(:secret_logger).and_return(double('Logger').as_null_object)
      action
    end

    before do
      # Default any domain lookup to nil so a smuggled-domain lookup would fail
      # loudly ("Unknown domain") rather than silently pass.
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with(host_domain).and_return(host_record)
    end

    it 'drops the smuggled share_domain at the ingestion boundary (process_params)' do
      # process_params already ran inside initialize; the guest value never landed.
      expect(subject.share_domain).to be_nil
    end

    it 'resolves the share domain to the Host header through raise_concerns' do
      expect { subject.raise_concerns }.not_to raise_error
      expect(subject.share_domain).to eq(host_domain)
    end

    it 'never looks up the smuggled domain record end-to-end' do
      subject.raise_concerns
      expect(Onetime::CustomDomain).to have_received(:from_display_domain).with(host_domain)
      expect(Onetime::CustomDomain).not_to have_received(:from_display_domain).with(smuggled_domain)
    end
  end
end
