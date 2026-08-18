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
#   2. ENTITLEMENT. The org-wide listing is gated at the same admin/owner
#      entitlement as the sibling org-wide surface (ListSecretActivity's
#      audit_logs), rather than the member-level api_access that let the
#      least-privileged role read the whole organization's receipts.
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
      planid: 'anonymous',
      email: 'caller@example.com',
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

          # Shortids are this product's established safe form for cross-member
          # surfaces (ListSecretActivity emits shortids only). They must stay
          # Strings: the V3 contract types identifier/key as required,
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
end
