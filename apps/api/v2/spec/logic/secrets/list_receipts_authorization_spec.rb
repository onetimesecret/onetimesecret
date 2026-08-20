# apps/api/v2/spec/logic/secrets/list_receipts_authorization_spec.rb
#
# frozen_string_literal: true

# ============================================================================
# Regression coverage for the 2026-08-14 appsec review, finding H-1:
# "Any organization member can harvest every colleague's secret bearer tokens
# via receipt/recent?scope=org".
#
# Two independent controls are asserted here, because either one alone leaves
# the finding partly open:
#
#   1. REDACTION (the load-bearing one). scope=org and scope=domain return
#      receipts created by other members. In this product an identifier IS a
#      capability — secret_identifier alone is sufficient to reveal the secret,
#      since the reveal path performs no ownership check by design — so records
#      the caller does not own must come back without it, and without the
#      receipt identifier/key that authorize burning.
#
#   2. ENTITLEMENT. The org-wide listing requires audit_logs rather than the
#      member-level api_access that let the least-privileged role read the whole
#      organization's receipts.
#
# Three follow-up findings from the review of that fix are covered at the
# bottom of this file: the ORGS_AUDIT_LOGS_ENABLED instance kill-switch (A),
# scope=domain sidestepping the org gate (B, appsec M-6), and the redaction
# guard failing open for scopes added later (C).
#
# These are doubles-only: the security property under test is a serialization
# and gating decision, so it is asserted directly rather than through Familia
# sorted sets. See show_secret_spec.rb for the real-model variant of the
# surrounding flow.
# ============================================================================

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

RSpec.describe V2::Logic::Secrets::ListReceipts do
  # A capability-bearing safe_dump, shaped like the real one. The values below
  # are the ones that must never reach a non-owner.
  def receipt_dump(identifier:, secret_identifier:)
    {
      identifier: identifier,
      key: identifier,
      shortid: identifier.slice(0, 8),
      secret_identifier: secret_identifier,
      secret_shortid: secret_identifier.slice(0, 8),
      state: 'new',
      updated: 1_755_000_000.0,
      is_destroyed: false,
    }
  end

  # owner_of is the customer double this receipt reports as its owner; any
  # other caller gets false from owner?, exactly like Receipt#owner? comparing
  # objid to owner_id.
  def receipt_double(identifier:, secret_identifier:, owner_of:)
    dump = receipt_dump(identifier: identifier, secret_identifier: secret_identifier)
    instance_double(Onetime::Receipt).tap do |receipt|
      allow(receipt).to receive(:safe_dump).and_return(dump)
      allow(receipt).to receive(:owner?) { |candidate| candidate.equal?(owner_of) }
    end
  end

  let(:caller_customer) do
    double(
      'Customer',
      anonymous?: false,
      custid: 'caller@example.com',
      objid: 'cust_caller',
      extid: 'ur_caller',
      planid: 'anonymous',
      email: 'caller@example.com',
      # has_system_role?('colonel') — reached by require_entitlement_in! —
      # short-circuits on the unverified check before touching #role.
      verified?: false,
    )
  end

  let(:colleague) do
    double(
      'Customer',
      anonymous?: false,
      custid: 'colleague@example.com',
      objid: 'cust_colleague',
      planid: 'anonymous',
      email: 'colleague@example.com',
    )
  end

  let(:session) do
    double('Session', anonymous?: false, custid: 'caller@example.com', identifier: 'sess_caller')
  end

  let(:strategy_result) do
    double('StrategyResult', session: session, user: caller_customer, metadata: { organization_context: {} })
  end

  # The colleague's receipt: a live share link the caller must not receive.
  let(:foreign_receipt) do
    receipt_double(
      identifier: 'ffffffffreceipt0000000000000000000000000000000000000000000000ffff',
      secret_identifier: 'ffffffffsecret00000000000000000000000000000000000000000000000fff',
      owner_of: colleague,
    )
  end

  # The caller's own receipt, which must be returned intact.
  let(:own_receipt) do
    receipt_double(
      identifier: 'aaaaaaaareceipt0000000000000000000000000000000000000000000000aaaa',
      secret_identifier: 'aaaaaaaasecret00000000000000000000000000000000000000000000000aaa',
      owner_of: caller_customer,
    )
  end

  def build_logic(params)
    described_class.new(strategy_result, params)
  end

  # auth_membership is the ADR-012 Stage 3 authority: require_entitlement!
  # consults auth_membership.can?, not auth_org.can?.
  def stub_entitlements(logic, granted)
    org        = double('Organization', planid: 'testplan', extid: 'org_test')
    membership = double('OrganizationMembership', active?: true, status: 'active')
    allow(membership).to receive(:can?) { |entitlement| granted.include?(entitlement.to_s) }
    allow(logic).to receive(:auth_org).and_return(org)
    allow(logic).to receive(:auth_membership).and_return(membership)
    logic
  end

  # Override features.organizations.audit_logs_enabled without disturbing the
  # rest of the booted config. The production reader compares the STRING form,
  # so the tests drive it with both false and 'false'.
  def stub_audit_logs_flag(value)
    conf                = OT.conf.dup
    features            = (conf['features'] || {}).dup
    organizations       = (features['organizations'] || {}).dup
    organizations['audit_logs_enabled'] = value
    features['organizations']           = organizations
    conf['features']                    = features
    allow(OT).to receive(:conf).and_return(conf)
  end

  before(:all) do
    OT.boot!(:test)
  end

  describe 'capability redaction in cross-member scopes' do
    %w[org domain].each do |cross_member_scope|
      context "with scope=#{cross_member_scope}" do
        subject(:logic) { build_logic('scope' => cross_member_scope, 'domain_extid' => 'dom_example') }

        it "withholds another member's secret_identifier" do
          record = logic.send(:safe_dump_for, foreign_receipt)

          expect(record[:secret_identifier]).to be_nil
        end

        it "withholds another member's receipt identifier and key" do
          record = logic.send(:safe_dump_for, foreign_receipt)

          full_identifier = foreign_receipt.safe_dump[:identifier]
          expect(record[:identifier]).not_to eq(full_identifier)
          expect(record[:key]).not_to eq(full_identifier)
        end

        it 'collapses identifier and key to the non-capability shortid' do
          record  = logic.send(:safe_dump_for, foreign_receipt)
          shortid = foreign_receipt.safe_dump[:shortid]

          # The V3 contract types identifier/key as required,
          # non-nullable strings inside a strict array, so a nil here would
          # fail the record and blank the entire response.
          expect(record[:identifier]).to eq(shortid)
          expect(record[:key]).to eq(shortid)
          expect(record[:identifier]).to be_a(String)
          expect(record[:key]).to be_a(String)
        end

        it 'leaves the requesting customer\'s own receipt untouched' do
          record = logic.send(:safe_dump_for, own_receipt)

          expect(record).to eq(own_receipt.safe_dump)
        end
      end
    end
  end

  describe 'the default (own receipts) scope' do
    subject(:logic) { build_logic({}) }

    it 'is left byte-identical, since the caller owns everything in it' do
      record = logic.send(:safe_dump_for, own_receipt)

      expect(record).to eq(own_receipt.safe_dump)
    end
  end

  describe 'entitlement gating' do
    it 'refuses scope=org for a member holding only api_access' do
      logic = stub_entitlements(build_logic('scope' => 'org'), %w[api_access])

      expect { logic.raise_concerns }.to raise_error(Onetime::EntitlementRequired) { |error|
        expect(error.entitlement.to_s).to eq('audit_logs')
      }
    end

    it 'allows scope=org for an admin or owner holding audit_logs' do
      logic = stub_entitlements(build_logic('scope' => 'org'), %w[api_access audit_logs])

      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'still allows the default scope on api_access alone' do
      logic = stub_entitlements(build_logic({}), %w[api_access])

      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  # ==========================================================================
  # FINDING A — the instance kill-switch must disable organization-wide receipt
  # visibility. Otherwise an operator who disables the feature still has the
  # receipt stream readable over the API.
  # ==========================================================================
  describe 'the audit_logs_enabled instance flag' do
    # An admin/owner: the flag must darken the surface for the roles that
    # would otherwise pass the entitlement gate, or it darkens nothing.
    def privileged(params)
      stub_entitlements(build_logic(params), %w[api_access audit_logs])
    end

    it 'darkens scope=org even for a caller holding audit_logs' do
      stub_audit_logs_flag(false)
      logic = privileged('scope' => 'org')

      expect { logic.raise_concerns }.to raise_error(OT::FormError) { |error|
        expect(error.error_type).to eq(:forbidden)
      }
    end

    it 'darkens scope=domain too, since it is the same org-wide stream' do
      stub_audit_logs_flag(false)
      logic = privileged('scope' => 'domain', 'domain_extid' => 'dom_example')

      expect { logic.raise_concerns }.to raise_error(OT::FormError) { |error|
        expect(error.error_type).to eq(:forbidden)
      }
    end

    it 'honours the string form' do
      # A hand-edited config can yield the string; a strict `== false` would
      # leave the API serving the stream after the feature is disabled.
      stub_audit_logs_flag('false')
      logic = privileged('scope' => 'org')

      expect { logic.raise_concerns }.to raise_error(OT::FormError)
    end

    it 'leaves the default (own receipts) scope alone' do
      stub_audit_logs_flag(false)
      logic = stub_entitlements(build_logic({}), %w[api_access])

      expect { logic.raise_concerns }.not_to raise_error
    end

    # The denial log fires on every refused scope=org/scope=domain request. On
    # a deployment with legacy (pre-v0.22) customers custid IS the email
    # address, so an actor: cust.custid payload is a continuous PII feed into
    # the structured logs. The payload is pinned to the opaque extid here.
    it 'records the denial against the extid, never the email-bearing custid' do
      stub_audit_logs_flag(false)
      logic    = privileged('scope' => 'org')
      emitted  = []
      allow(OT).to receive(:info) { |*msgs, **payload| emitted << [msgs.join(' '), payload] }

      expect { logic.raise_concerns }.to raise_error(OT::FormError)

      message, payload = emitted.find { |msg, _| msg.include?('[ListReceipts]') }
      expect(payload).to eq(scope: 'org', actor: 'ur_caller')
      expect(payload).not_to have_key(:custid)
      # Scans the whole emitted record rather than one key, so a future payload
      # addition carrying an address fails here too.
      record = [message, payload.values.join(' ')].join(' ')
      expect(record).not_to include(caller_customer.custid)
      expect(record).not_to include('@')
    end

    it 'defaults to enabled when the key is absent (older config file)' do
      conf = OT.conf.dup
      conf['features'] = (conf['features'] || {}).dup.tap { |f| f['organizations'] = {} }
      allow(OT).to receive(:conf).and_return(conf)
      logic = privileged('scope' => 'org')

      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  # ==========================================================================
  # FINDING B — scope=domain must clear the same bar as scope=org (appsec M-6).
  #
  # A `member` refused scope=org used to re-run the query as
  # scope=domain&domain_extid=<one of the org's domains> and receive every
  # colleague's domain-bound receipt metadata. The entitlement is checked in
  # the DOMAIN's organization, not the caller's auth_org.
  # ==========================================================================
  describe 'the domain scope' do
    let(:domain_org) { double('Organization', objid: 'org_domain_owner', planid: 'domainplan', extid: 'org_dom') }

    let(:domain) do
      instance_double(
        Onetime::CustomDomain,
        display_domain: 'secrets.example.com',
        primary_organization: domain_org,
      ).tap do |dom|
        allow(dom).to receive(:accessible_by?).and_return(true)
        allow(dom).to receive(:receipts).and_return(double('SortedSet', rangebyscore: %w[receipt_1]))
      end
    end

    # The caller's membership in the DOMAIN's organization, which is what
    # require_entitlement_in! loads (not auth_membership).
    def stub_domain_membership(granted)
      membership = double('OrganizationMembership', active?: true, status: 'active')
      allow(membership).to receive(:can?) { |entitlement| granted.include?(entitlement.to_s) }
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer).and_return(membership)
      membership
    end

    def domain_logic(granted_in_auth_org)
      logic = stub_entitlements(
        build_logic('scope' => 'domain', 'domain_extid' => 'dom_example'),
        granted_in_auth_org,
      )
      allow(Onetime::CustomDomain).to receive(:find_by_extid).and_return(domain)
      logic.process_params
      logic
    end

    it 'refuses a plain member, who is correctly refused scope=org' do
      stub_domain_membership(%w[api_access])
      logic = domain_logic(%w[api_access])

      expect { logic.send(:query_domain_receipts) }.to raise_error(Onetime::EntitlementRequired) { |error|
        expect(error.entitlement.to_s).to eq('audit_logs')
      }
    end

    it 'allows an admin or owner of the domain\'s organization' do
      stub_domain_membership(%w[api_access audit_logs])
      logic = domain_logic(%w[api_access])

      expect { logic.send(:query_domain_receipts) }.not_to raise_error
    end

    it 'evaluates the entitlement in the domain\'s org, not the caller\'s auth_org' do
      stub_domain_membership(%w[api_access audit_logs])
      logic = domain_logic(%w[api_access])

      logic.send(:query_domain_receipts)

      # auth_org here is 'org_test' (see stub_entitlements); the lookup must
      # use the domain's owning org, which is the org the records belong to.
      expect(Onetime::OrganizationMembership).to have_received(:find_by_org_customer)
        .with('org_domain_owner', 'cust_caller')
    end

    it 'refuses a non-member on the membership check, before the entitlement' do
      # accessible_by? survives as the first gate: the new entitlement is in
      # addition to it, not a replacement.
      allow(domain).to receive(:accessible_by?).and_return(false)
      stub_domain_membership(%w[api_access audit_logs])
      logic = domain_logic(%w[api_access audit_logs])

      expect { logic.send(:query_domain_receipts) }.to raise_error(OT::FormError, /Access denied to domain/)
      expect(Onetime::OrganizationMembership).not_to have_received(:find_by_org_customer)
    end

    # ========================================================================
    # A domain with damaged ownership metadata: org_id blank, or pointing at an
    # organization that has since been deleted. primary_organization answers
    # nil, and that nil used to travel straight into require_entitlement_in!,
    # which rejects it with a bare Onetime::Problem — an unanswerable 500 on a
    # data defect the caller cannot act on.
    #
    # accessible_by? refuses such a domain today (it resolves the same org and
    # returns false), so this was not a reachable 500. The guard is asserted
    # anyway because it makes the invariant local: relaxing accessible_by?
    # later must not be able to re-open the crash.
    # ========================================================================
    describe 'a domain whose organization cannot be resolved' do
      let(:orphaned_domain) do
        instance_double(
          Onetime::CustomDomain,
          display_domain: 'orphan.example.com',
          extid: 'dm_orphan',
          primary_organization: nil,
        ).tap do |dom|
          # Deliberately generous: the guard must hold on its own, not because
          # the membership check happens to refuse first.
          allow(dom).to receive(:accessible_by?).and_return(true)
          allow(dom).to receive(:receipts).and_return(double('SortedSet', rangebyscore: %w[receipt_1]))
        end
      end

      def orphan_logic
        logic = stub_entitlements(
          build_logic('scope' => 'domain', 'domain_extid' => 'dm_orphan'),
          %w[api_access],
        )
        allow(Onetime::CustomDomain).to receive(:find_by_extid).and_return(orphaned_domain)
        logic.process_params
        logic
      end

      def capture_form_error
        yield
        raise 'expected a FormError, none was raised'
      rescue OT::FormError => ex
        ex
      end

      it 'answers a handled forbidden error, not a 500' do
        stub_domain_membership(%w[api_access audit_logs])
        logic = orphan_logic

        expect { logic.send(:query_domain_receipts) }.to raise_error(OT::FormError) { |error|
          expect(error.error_type).to eq(:forbidden)
        }
      end

      it 'never hands require_entitlement_in! a nil organization' do
        stub_domain_membership(%w[api_access audit_logs])
        logic = orphan_logic
        allow(logic).to receive(:require_entitlement_in!).and_call_original

        expect { logic.send(:query_domain_receipts) }.to raise_error(OT::FormError)

        # Stronger than asserting it was not called WITH nil: the entitlement
        # decision has no meaning without an organization, so it must not be
        # attempted at all.
        expect(logic).not_to have_received(:require_entitlement_in!)
      end

      it 'answers exactly what a plain access denial answers' do
        # Two different internal states, one public response. Any divergence —
        # message, error_type, field, error_key — turns the endpoint into an
        # oracle for which domains carry broken ownership metadata.
        stub_domain_membership(%w[api_access audit_logs])
        orphan_error = capture_form_error { orphan_logic.send(:query_domain_receipts) }

        denied_logic = domain_logic(%w[api_access audit_logs])
        allow(domain).to receive(:accessible_by?).and_return(false)
        denied_error = capture_form_error { denied_logic.send(:query_domain_receipts) }

        expect(orphan_error.to_h).to eq(denied_error.to_h)
        expect(orphan_error.message).to eq(denied_error.message)
      end

      # Same reasoning as the scope=org denial log above: custid IS the email
      # address on legacy (pre-v0.22) records, and org_id is an internal objid
      # that identifies the very organization the request could not reach.
      it 'logs the orphan against opaque identifiers only' do
        stub_domain_membership(%w[api_access audit_logs])
        logic   = orphan_logic
        emitted = []
        allow(OT).to receive(:lw) { |*msgs, **payload| emitted << [msgs.join(' '), payload] }

        expect { logic.send(:query_domain_receipts) }.to raise_error(OT::FormError)

        message, payload = emitted.find { |msg, _| msg.include?('[ListReceipts]') }
        expect(payload).to eq(domain: 'dm_orphan', actor: 'ur_caller')
        expect(payload).not_to have_key(:org_id)
        expect(payload).not_to have_key(:custid)
        # Scans the whole emitted record rather than named keys, so a future
        # payload addition carrying an address or an objid fails here too.
        record = [message, payload.values.join(' ')].join(' ')
        expect(record).not_to include(caller_customer.custid)
        expect(record).not_to include('@')
      end
    end
  end

  # ==========================================================================
  # FINDING C — redaction must fail CLOSED for scopes added later.
  #
  # The guard is an exemption list (OWN_INDEX_SCOPES), not a list of
  # cross-member scopes: a new scope inherits the withholding rather than
  # reopening H-1 silently. This exercises safe_dump_for directly, so it does
  # not depend on the #process case statement having grown the scope yet.
  # ==========================================================================
  describe 'a scope the redaction guard has never heard of' do
    subject(:logic) { build_logic('scope' => 'some_future_scope') }

    it "withholds another member's capability tokens by default" do
      record  = logic.send(:safe_dump_for, foreign_receipt)
      shortid = foreign_receipt.safe_dump[:shortid]

      expect(record[:secret_identifier]).to be_nil
      expect(record[:identifier]).to eq(shortid)
      expect(record[:key]).to eq(shortid)
    end

    it 'still returns the caller\'s own receipt intact' do
      record = logic.send(:safe_dump_for, own_receipt)

      expect(record).to eq(own_receipt.safe_dump)
    end
  end

  # ==========================================================================
  # OPERATOR PRECONDITION — the two entitlement gates above are only
  # satisfiable if a live plan grants audit_logs.
  #
  # Effective entitlements are the org's plan ∩ ROLE_ENTITLEMENTS[role], so on
  # a billing-enabled install whose catalog grants audit_logs nowhere, scope=org
  # and scope=domain 403 for EVERY caller, owners included. The example catalog
  # is what an operator starts from, and it previously defined audit_logs
  # without granting it on any active plan (the only grant sat in the
  # commented-out team tier), so the gates shipped unsatisfiable.
  #
  # Asserted next to the gates rather than in a billing spec: the gate and the
  # catalog grant that makes it reachable have to move together.
  # ==========================================================================
  describe 'the shipped example plan catalog' do
    let(:example_catalog) do
      path = File.join(Onetime::HOME, 'etc', 'examples', 'billing.example.yaml')
      YAML.safe_load(ERB.new(File.read(path)).result, aliases: true)
    end

    let(:granting_plans) do
      example_catalog.fetch('plans').select do |_plan_id, plan|
        Array(plan['entitlements']).include?('audit_logs')
      end
    end

    it 'defines audit_logs' do
      expect(example_catalog.fetch('entitlements')).to have_key('audit_logs')
    end

    # An ACTIVE plan: commented-out plans are not parsed, so a grant that only
    # exists inside the commented team tier leaves both scopes unreachable.
    it 'grants audit_logs on an active paid plan' do
      expect(granting_plans.keys).to include('identity_plus_v1')
    end

    it 'withholds it from the free tier' do
      expect(Array(example_catalog.dig('plans', 'free_v1', 'entitlements'))).not_to include('audit_logs')
    end
  end
end
