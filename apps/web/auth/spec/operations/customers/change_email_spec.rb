# apps/web/auth/spec/operations/customers/change_email_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::ChangeEmail.
#
# This is a cross-store mutation (Postgres accounts row + Redis Customer and
# three indexes) with no distributed transaction, so the contract these examples
# pin down is mostly about ORDER and FAILURE:
#
#   * SQL is written BEFORE any Redis write (a SQL failure must leave Redis clean)
#   * the class email index is re-keyed with the OLD address, before save
#   * a Redis failure after the SQL commit yields :partial — never a raise past a
#     committed mutation, because that would lose the audit
#   * the compensating SQL write-back fires ONLY when the Customer hash never
#     committed the new address (otherwise it would manufacture drift)
#   * exactly one `customer.change_email` audit event, with OBSCURED addresses
#
# Every collaborator is stubbed: no datastore, no auth DB, no mail.
#
# Run: bundle exec rspec apps/web/auth/spec/operations/customers/change_email_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'auth/database'
require 'auth/operations/customers/change_email'

RSpec.describe Auth::Operations::Customers::ChangeEmail do
  # Ordered trace of the cross-store writes, so ordering is asserted on facts
  # rather than on RSpec's `.ordered` bookkeeping.
  let(:trace) { [] }

  let(:old_email) { 'old@example.com' }
  let(:new_email) { 'new@example.com' }

  let(:pending_change) { double('pending_email_change', to_s: '', delete!: true) }
  let(:pending_status) { double('pending_email_delivery_status', delete!: true) }

  let(:customer) do
    cust = double(
      'Customer',
      extid: 'ur_c',
      objid: 'obj_c',
      anonymous?: false,
      locale: 'en',
      obscure_email: 'ol***@e***.com',
      organization_instances: [],
      pending_email_change: pending_change,
      pending_email_delivery_status: pending_status,
    )
    allow(cust).to receive(:email).and_return(old_email)
    allow(cust).to receive(:email=) { |value| trace << [:customer_email_assigned, value] }
    allow(cust).to receive(:update_in_class_email_index) { |old| trace << [:class_index_rekey, old] }
    allow(cust).to receive(:update_in_organization_email_index) { |org, old| trace << [:org_index_rekey, org, old] }
    allow(cust).to receive(:save) { trace << [:customer_save] }
    # Verification state, only consulted on the forced-clear fallback. `hget` is
    # the PERSISTED field and is what the fallback reads; `verified?` is the
    # in-memory predicate. They are deliberately separate doubles because the
    # wrapper assigns the attribute before saving, so the two disagree exactly
    # when the fallback matters.
    allow(cust).to receive(:verified?).and_return(true)
    allow(cust).to receive(:hget).with('verified').and_return('true')
    allow(cust).to receive(:verified=) { |value| trace << [:customer_verified_assigned, value] }
    allow(cust).to receive(:verified_by=)
    cust
  end

  # --- Redis index doubles -------------------------------------------------
  # hsetnx: 1 == "the claim was ours" (only claimed when no accounts row carries
  # the claim for us; with a row present the op never calls it).
  #
  # The claim RELEASE is a Lua compare-and-delete rather than a method on the
  # index, so it goes through the raw client — hence dbclient/dbkey. `eval: 1`
  # is the default "the field was still ours and is now gone" answer.
  let(:index_dbclient)      { double('index dbclient', eval: 1) }
  let(:index_dbkey)         { 'customer:email_index' }
  let(:email_index) do
    double('Customer.email_index', get: nil, hsetnx: 1, dbclient: index_dbclient, dbkey: index_dbkey)
  end
  let(:contact_email_index) { double('Organization.contact_email_index', get: nil) }

  # --- SQL doubles ---------------------------------------------------------
  # db[:accounts].where(...)  is called with three different filters; each gets
  # its own leaf double so the examples can drive them independently.
  let(:my_account_row)  { { id: 42, email: old_email } }
  let(:collision_rows)  { [] }

  let(:by_external_id) { double('by_external_id') }
  let(:by_email)       { double('by_email') }
  let(:by_id)          { double('by_id') }
  # The row-scoped, status-conditional filter used by the forced verification
  # clear. A DISTINCT leaf from `by_id` on purpose: the whole point of that write
  # is that it can only ever touch a row that is still status_id 2.
  let(:by_id_verified) { double('by_id_verified') }
  let(:account_status) { { status_id: 2 } }
  let(:accounts)       { double('accounts') }
  let(:db)             { double('db') }

  # --- delegated ops -------------------------------------------------------
  let(:revoker)  { instance_double(Onetime::Operations::Sessions::RevokeAllForCustomer, call: nil) }
  let(:verifier) { instance_double(Auth::Operations::Customers::SetVerification, call: :success) }

  before do
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(OT).to receive(:info)
    allow(Onetime::Customer).to receive(:email_index).and_return(email_index)
    allow(Onetime::Organization).to receive(:contact_email_index).and_return(contact_email_index)
    allow(Onetime::EmailSuppression).to receive(:suppressed?).and_return(false)
    allow(Onetime::OrganizationMembership).to receive(:find_pending_by_email).and_return(nil)
    allow(Onetime::Secret).to receive(:find_by_identifier).and_return(nil)
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email)

    allow(Onetime::Operations::Sessions::RevokeAllForCustomer).to receive(:new).and_return(revoker)
    allow(Auth::Operations::Customers::SetVerification).to receive(:new).and_return(verifier)

    # SQL wiring
    allow(db).to receive(:[]).with(:accounts).and_return(accounts)
    allow(db).to receive(:transaction) { |&blk| blk.call }
    allow(accounts).to receive(:where).with(external_id: 'ur_c').and_return(by_external_id)
    allow(accounts).to receive(:where).with(email: new_email).and_return(by_email)
    allow(accounts).to receive(:where).with(id: 42).and_return(by_id)
    allow(by_external_id).to receive(:select).with(:id, :email).and_return(by_external_id)
    allow(by_external_id).to receive(:first).and_return(my_account_row)
    allow(by_email).to receive(:select).with(:id, :status_id).and_return(by_email)
    allow(by_email).to receive(:all) { collision_rows }
    allow(by_id).to receive(:update) do |attrs|
      trace << [:sql_update, attrs[:email]]
      1
    end

    # Forced-verification-clear wiring (row-scoped + status-conditional) and the
    # status probe the :no_change path uses.
    allow(accounts).to receive(:where).with(id: 42, status_id: 2).and_return(by_id_verified)
    allow(by_id_verified).to receive(:update) do |attrs|
      trace << [:sql_status_update, attrs[:status_id]]
      1
    end
    allow(by_id).to receive(:select).with(:status_id).and_return(by_id)
    allow(by_id).to receive(:first) { account_status }
  end

  def op(**overrides)
    described_class.new(
      **{
        customer: customer,
        new_email: new_email,
        actor: 'cli',
        dry_run: false,
        db: db,
      }.merge(overrides)
    )
  end

  # =========================================================================
  describe 'happy path' do
    it 'returns :success with every Result field populated' do
      result = op.call

      expect(result.status).to eq(:success)
      expect(result.extid).to eq('ur_c')
      expect(result.from).to eq(old_email)
      expect(result.to).to eq(new_email)
      expect(result.dry_run).to be false
      expect(result.auth_row_updated).to be true
      expect(result.orgs_reindexed).to eq(0)
      expect(result.sessions_revoked).to be true
      expect(result.verification_reset).to be true
      expect(result.warnings).to eq([])
    end

    it 'writes SQL BEFORE Redis, and re-keys the class index with the OLD address before save' do
      op.call

      expect(trace).to eq(
        [
          [:sql_update, new_email],
          [:customer_email_assigned, new_email],
          [:class_index_rekey, old_email],
          [:customer_save],
        ]
      )
    end

    it 'records exactly one audit event with OBSCURED addresses' do
      op.call

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once
      expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
        actor: 'cli',
        verb: 'customer.change_email',
        target: 'ur_c',
        result: :success,
        detail: hash_including(
          from: OT::Utils.obscure_email(old_email),
          to: OT::Utils.obscure_email(new_email),
          auth_row_updated: true,
          orgs_reindexed: 0,
          require_verification: true,
        ),
      )
    end

    it 'never puts a raw address in the audit detail' do
      op.call

      detail = nil
      expect(Onetime::ColonelAuditEvent).to have_received(:record) { |kwargs| detail = kwargs[:detail] }
      expect(detail[:from]).not_to eq(old_email)
      expect(detail[:to]).not_to eq(new_email)
    end

    it 'normalizes the new address once, for the collision check AND the stored value' do
      expect(email_index).to receive(:get).with(new_email).and_return(nil)

      result = op(new_email: '  NEW@Example.COM ').call

      expect(result.to).to eq(new_email)
      expect(trace).to include([:customer_email_assigned, new_email])
    end
  end

  # =========================================================================
  describe 'dry run (the default)' do
    it 'defaults to dry_run: true' do
      result = described_class.new(customer: customer, new_email: new_email, actor: 'cli', db: db).call

      expect(result.status).to eq(:planned)
      expect(result.dry_run).to be true
    end

    it 'mutates nothing and audits nothing' do
      op(dry_run: true).call

      expect(trace).to be_empty
      expect(customer).not_to have_received(:save)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    it 'reports how many orgs WOULD be re-indexed' do
      allow(customer).to receive(:organization_instances).and_return([double('org'), double('org')])

      expect(op(dry_run: true).call.orgs_reindexed).to eq(2)
    end
  end

  # =========================================================================
  describe 'guards' do
    it 'returns :not_found for a nil customer' do
      expect(op(customer: nil).call.status).to eq(:not_found)
    end

    it 'returns :not_found for an anonymous customer' do
      allow(customer).to receive(:anonymous?).and_return(true)

      expect(op.call.status).to eq(:not_found)
      expect(customer).not_to have_received(:save)
    end

    # A refusal is an ATTEMPTED privileged mutation — and this verb is the
    # highest-value account-takeover primitive an operator has, so a refused
    # attempt lands in the trail with the same verb/target as a success,
    # differing only in result:/detail. Addresses stay obscured.
    it 'returns :invalid_email and records ONE result: :failure event' do
      result = op(new_email: 'not-an-email').call

      expect(result.status).to eq(:invalid_email)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(
          actor: 'cli',
          verb: 'customer.change_email',
          target: 'ur_c',
          result: :failure,
          detail: hash_including(reason: 'invalid_email', dry_run: false),
        ),
      )
    end

    it 'returns :no_change when the normalized address matches the current one' do
      result = op(new_email: '  OLD@Example.com ').call

      expect(result.status).to eq(:no_change)
      expect(customer).not_to have_received(:save)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end

  # =========================================================================
  describe 'collision detection (three distinct sources)' do
    it 'source 1: the Redis email index already points the address at someone else' do
      allow(email_index).to receive(:get).with(new_email).and_return('obj_other')

      result = op.call

      expect(result.status).to eq(:email_taken)
      expect(trace).to be_empty
    end

    it 'ignores a Redis index entry that points at the target customer itself (drift, not a collision)' do
      allow(email_index).to receive(:get).with(new_email).and_return('obj_c')

      expect(op.call.status).to eq(:success)
    end

    it 'source 2: a LIVE accounts row already holds the address' do
      collision_rows.replace([{ id: 99, status_id: 2 }])

      result = op.call

      expect(result.status).to eq(:email_taken)
      expect(trace).to be_empty
    end

    it "ignores the target's own accounts row in the SQL probe" do
      collision_rows.replace([{ id: 42, status_id: 2 }])

      expect(op.call.status).to eq(:success)
    end

    it 'source 3: the unique constraint fires on the UPDATE (TOCTOU close-out)' do
      allow(by_id).to receive(:update).and_raise(Sequel::UniqueConstraintViolation, 'dup')

      result = op.call

      expect(result.status).to eq(:email_taken)
      expect(customer).not_to have_received(:save)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(
          verb: 'customer.change_email',
          target: 'ur_c',
          result: :failure,
          detail: hash_including(reason: 'email_taken'),
        ),
      )
    end

    # A CLOSED account (status_id 3) sits outside the partial unique index AND
    # outside Customer.email_exists?, so it is invisible to both normal checks.
    it 'treats an address held by a CLOSED account as taken by default' do
      collision_rows.replace([{ id: 99, status_id: 3 }])

      expect(op.call.status).to eq(:email_taken)
    end

    it 'allows closed-account reuse when explicitly requested, with a warning' do
      collision_rows.replace([{ id: 99, status_id: 3 }])

      result = op(allow_closed_account_reuse: true).call

      expect(result.status).to eq(:success)
      expect(result.warnings).to include(:new_address_held_by_closed_account)
    end

    it 'warns rather than silently passing when the SQL probe itself fails' do
      allow(by_email).to receive(:all).and_raise(StandardError, 'db down')

      result = op.call

      expect(result.status).to eq(:success)
      expect(result.warnings).to include(:sql_collision_probe_failed)
    end
  end

  # =========================================================================
  describe 'SQL failure leaves Redis untouched' do
    # The Onetime::AuditedFailure mechanism. This re-raise happens from the
    # MIDDLE of the swap, before record_audit ever runs, so without the macro
    # an attempted takeover that blew up left nothing at all in the trail.
    # Message expectation, not a store read: ColonelAuditEvent.record swallows
    # its own errors.
    it 're-raises a non-uniqueness SQL error, records ONE failure, no Customer write' do
      allow(by_id).to receive(:update).and_raise(StandardError, 'connection reset')

      expect { op.call }.to raise_error(StandardError, 'connection reset')
      expect(customer).not_to have_received(:save)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(
          actor: 'cli',
          # AUDIT_VERB, never the side-effect verb this op also emits.
          verb: 'customer.change_email',
          target: 'ur_c', # literal: a broken target lambda lands as 'unknown'
          result: :failure,
          detail: hash_including(
            error: 'StandardError', message: 'connection reset', dry_run: false,
          ),
        ),
      )
    end
  end

  # =========================================================================
  describe ':partial — Redis fails after the SQL commit' do
    it 'compensates the SQL row back to the old address when the Customer never committed' do
      allow(customer).to receive(:save).and_raise(StandardError, 'redis down')

      result = op.call

      expect(result.status).to eq(:partial)
      expect(result.warnings).to include(:auth_row_rolled_back)
      expect(trace).to eq(
        [
          [:sql_update, new_email],
          [:customer_email_assigned, new_email],
          [:class_index_rekey, old_email],
          [:sql_update, old_email], # the compensating write-back
        ]
      )
    end

    it 'still records exactly one audit event, with result: :partial' do
      allow(customer).to receive(:save).and_raise(StandardError, 'redis down')

      op.call

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(verb: 'customer.change_email', result: :partial)
      )
    end

    it 'reports auth_row_updated: false once the row has been rolled back' do
      allow(customer).to receive(:save).and_raise(StandardError, 'redis down')

      expect(op.call.auth_row_updated).to be false
    end

    # Rolling SQL back here would MANUFACTURE the drift the compensation exists
    # to prevent: both authoritative stores already hold the new address.
    # Driven through the pending-marker teardown, which is deliberately NOT
    # rescued (a surviving marker means a live token can revert the change).
    it 'does NOT roll SQL back when the Customer hash already committed' do
      allow(customer).to receive(:pending_email_change).and_raise(StandardError, 'redis blip')

      result = op.call

      expect(result.status).to eq(:partial)
      expect(result.warnings).to include(:secondary_writes_incomplete)
      expect(result.auth_row_updated).to be true
      expect(trace.count { |entry| entry.first == :sql_update }).to eq(1)
    end

    # In this sub-case the swap LANDED: both authoritative stores hold the new
    # address and only secondary indexes are behind. So the FULL follow-up phase
    # is owed exactly as it is on :success. Returning without it would drop the
    # "an email change revokes every session" property on precisely the messy
    # path — every session, including the current one, would survive a change
    # the user is told failed — and would leave the account flagged verified on
    # an address nobody has proven ownership of.
    context 'when the Customer hash already committed (the swap landed)' do
      before { allow(customer).to receive(:pending_email_change).and_raise(StandardError, 'redis blip') }

      it 'still revokes sessions, through the same op :success uses' do
        result = op.call

        expect(Onetime::Operations::Sessions::RevokeAllForCustomer).to have_received(:new).with(
          custid: 'ur_c', actor: 'cli'
        )
        expect(revoker).to have_received(:call)
        expect(result.sessions_revoked).to be true
      end

      it 'still mails BOTH addresses (D36)' do
        op.call

        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).twice
        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).with(
          :email_changed, hash_including(recipient: old_email), hash_including(fallback: :async_thread)
        )
        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).with(
          :email_changed, hash_including(recipient: new_email), hash_including(fallback: :async_thread)
        )
      end

      it 'still honours revoke_sessions: false and notify: false' do
        result = op(revoke_sessions: false, notify: false).call

        expect(Onetime::Operations::Sessions::RevokeAllForCustomer).not_to have_received(:new)
        expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email)
        expect(result.sessions_revoked).to be false
      end

      # The follow-up is NOT best-effort cover for every partial: it is owed only
      # where the swap landed. It must not degrade into a warning either.
      it 'reports a revocation that failed rather than claiming one' do
        allow(revoker).to receive(:call).and_raise(StandardError, 'redis gone')

        result = op.call

        expect(result.sessions_revoked).to be false
        expect(result.warnings).to include(:sessions_revoke_failed)
      end

      # The one that actually bites: an operator-initiated change that half-lands
      # must not leave the account flagged Verified on an address nobody proved.
      # Same delegate, same require_verification gate :success uses.
      it 'still resets verification, through the same wrapper :success uses' do
        result = op.call

        # enforce_interlocks: false — a credential-provenance reset, not an
        # administrative unverify (#4328). It must never be refused by the
        # last-colonel interlock: leaving a colonel "verified" against an
        # address nobody proved is worse than the lockout that guard prevents.
        expect(Auth::Operations::Customers::SetVerification).to have_received(:new).with(
          customer: customer, verified: false, actor: 'cli', verified_by: nil,
          enforce_interlocks: false, db: db
        )
        expect(verifier).to have_received(:call)
        expect(result.verification_reset).to be true
      end

      it 'honours require_verification: false exactly as :success does' do
        result = op(require_verification: false).call

        expect(Auth::Operations::Customers::SetVerification).not_to have_received(:new)
        expect(result.verification_reset).to be false
      end

      # The status is already :partial and there is nothing below it, so the
      # signal the :success path carries as a STATUS is carried here as the
      # identically named warning — the operator owes the same
      # `bin/ots customers unverify` remediation either way.
      context 'when the reset cannot be confirmed' do
        before do
          allow(verifier).to receive(:call).and_raise(StandardError, 'no auth db')
          allow(by_id_verified).to receive(:update).and_raise(StandardError, 'db gone')
        end

        it 'warns :verification_not_reset without moving the status off :partial' do
          result = op.call

          expect(result.status).to eq(:partial)
          expect(result.verification_reset).to be false
          expect(result.warnings).to include(
            :secondary_writes_incomplete, :verification_reset_failed,
            :verification_still_set, :verification_not_reset
          )
        end

        it 'carries those warnings into the single :partial audit event' do
          op.call

          expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
            hash_including(
              verb: 'customer.change_email',
              result: :partial,
              detail: hash_including(warnings: include(:verification_not_reset, :verification_still_set)),
            )
          )
        end
      end

      # The fail-closed fallback is owed here too: the wrapper failing must not
      # mean the flag simply stays up.
      it 'force-clears row-scoped when the wrapper fails, and reports the clear' do
        allow(verifier).to receive(:call).and_raise(StandardError, 'no auth db')

        result = op.call

        expect(result.status).to eq(:partial)
        expect(result.verification_reset).to be true
        expect(result.warnings).to include(:verification_reset_failed, :verification_force_cleared)
        expect(result.warnings).not_to include(:verification_not_reset)
        expect(trace).to include([:sql_status_update, 1], [:customer_verified_assigned, false])
      end
    end

    # The mirror image: the swap did NOT land (the accounts row was rolled back
    # to the old address), so revoking sessions, unverifying and mailing a change
    # notice would all be reacting to something that never happened.
    it 'runs NO follow-up when the Customer never committed' do
      allow(customer).to receive(:save).and_raise(StandardError, 'redis down')

      result = op.call

      expect(Onetime::Operations::Sessions::RevokeAllForCustomer).not_to have_received(:new)
      expect(Auth::Operations::Customers::SetVerification).not_to have_received(:new)
      expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email)
      expect(result.sessions_revoked).to be false
      expect(result.verification_reset).to be false
    end
  end

  # =========================================================================
  describe 'organization indexes' do
    let(:org_a) { double('org_a', extid: 'og_a', identifier: 'og_a', is_default: 'false', contact_email: '') }
    let(:org_b) { double('org_b', extid: 'og_b', identifier: 'og_b', is_default: 'false', contact_email: '') }

    before { allow(customer).to receive(:organization_instances).and_return([org_a, org_b]) }

    it 're-keys the org-scoped index once per org, with the OLD address' do
      result = op.call

      expect(result.orgs_reindexed).to eq(2)
      expect(trace).to include([:org_index_rekey, org_a, old_email], [:org_index_rekey, org_b, old_email])
    end

    it 'warns and keeps going when one org fails' do
      allow(customer).to receive(:update_in_organization_email_index) do |org, old|
        raise StandardError, 'boom' if org == org_a

        trace << [:org_index_rekey, org, old]
      end

      result = op.call

      expect(result.status).to eq(:success)
      expect(result.orgs_reindexed).to eq(1)
      expect(result.warnings).to include(:org_email_index_failed)
    end
  end

  # =========================================================================
  describe 'organization contact_email (D39)' do
    let(:default_org) do
      org = double('default_org', extid: 'og_d', identifier: 'og_d', is_default: 'true', contact_email: old_email)
      # Stubbed so the negative assertions below are real spy assertions, not
      # "that object is not a spy" errors.
      allow(org).to receive(:billing_email=)
      allow(org).to receive(:stripe_checkout_email=)
      allow(org).to receive(:email_hash=)
      allow(org).to receive(:contact_email=) { |value| trace << [:org_contact_assigned, value] }
      allow(org).to receive(:update_in_class_contact_email_index) { |old| trace << [:org_contact_rekey, old] }
      allow(org).to receive(:save) { trace << [:org_save] }
      org
    end

    let(:shared_org) do
      org = double('shared_org', extid: 'og_s', identifier: 'og_s', is_default: 'false', contact_email: old_email)
      allow(org).to receive(:contact_email=)
      allow(org).to receive(:save)
      org
    end

    it 'rewrites the contact of a default org whose contact_email is the OLD address' do
      allow(customer).to receive(:organization_instances).and_return([default_org])

      result = op.call

      expect(result.warnings).to include(:org_contact_email_updated)
      expect(trace).to include([:org_contact_assigned, new_email], [:org_contact_rekey, old_email], [:org_save])
    end

    it 'NEVER rewrites a shared (non-default) org contact' do
      allow(customer).to receive(:organization_instances).and_return([shared_org])

      result = op.call

      expect(result.warnings).not_to include(:org_contact_email_updated)
      expect(shared_org).not_to have_received(:contact_email=)
      expect(shared_org).not_to have_received(:save)
    end

    it 'skips (and warns) when another org already holds the new address as its contact' do
      allow(customer).to receive(:organization_instances).and_return([default_org])
      allow(contact_email_index).to receive(:get).with(new_email).and_return('og_other')

      result = op.call

      expect(result.warnings).to include(:org_contact_email_conflict)
      expect(default_org).not_to have_received(:contact_email=)
    end

    it 'never touches billing_email / stripe_checkout_email / email_hash' do
      allow(customer).to receive(:organization_instances).and_return([default_org])

      op.call

      %i[billing_email= stripe_checkout_email= email_hash=].each do |setter|
        expect(default_org).not_to have_received(setter)
      end
    end
  end

  # =========================================================================
  describe 'pending self-service email change' do
    it 'clears both pending markers' do
      op.call

      expect(pending_change).to have_received(:delete!)
      expect(pending_status).to have_received(:delete!)
    end

    it 'destroys a live pending verification secret and warns' do
      secret = double('Secret', destroy!: true)
      allow(customer).to receive(:pending_email_change).and_return(
        double('pending', to_s: 'tok_live', delete!: true)
      )
      allow(Onetime::Secret).to receive(:find_by_identifier).with('tok_live').and_return(secret)

      result = op.call

      expect(secret).to have_received(:destroy!)
      expect(result.warnings).to include(:pending_self_service_change_cleared)
    end
  end

  # =========================================================================
  describe 'delegation to sibling ops (one audit event per VERB)' do
    it 'delegates session revocation to RevokeAllForCustomer' do
      op.call

      expect(Onetime::Operations::Sessions::RevokeAllForCustomer).to have_received(:new).with(
        custid: 'ur_c', actor: 'cli'
      )
    end

    it 'skips session revocation when revoke_sessions is false' do
      result = op(revoke_sessions: false).call

      expect(Onetime::Operations::Sessions::RevokeAllForCustomer).not_to have_received(:new)
      expect(result.sessions_revoked).to be false
    end

    it 'resets verification through SetVerification when require_verification is true' do
      op.call

      # See the note on the :partial example: this reset is a provenance reset,
      # so it opts out of #4328's administrative unverify interlocks.
      expect(Auth::Operations::Customers::SetVerification).to have_received(:new).with(
        customer: customer, verified: false, actor: 'cli', verified_by: nil,
        enforce_interlocks: false, db: db
      )
    end

    it 'leaves verification alone when require_verification is false (the token path)' do
      result = op(require_verification: false).call

      expect(Auth::Operations::Customers::SetVerification).not_to have_received(:new)
      expect(result.verification_reset).to be false
    end
  end

  # =========================================================================
  # An account left flagged VERIFIED on an address nobody has proven ownership
  # of is the exact state require_verification exists to prevent. The swap has
  # already committed by the time the reset runs, so this must not raise — but
  # it must not read as clean success either.
  describe 'verification reset failure (the swap has already committed)' do
    context 'when the wrapper RAISES' do
      before { allow(verifier).to receive(:call).and_raise(StandardError, 'no auth db') }

      it 'force-clears the flag row-scoped and reports it, without raising' do
        result = op.call

        expect(result.status).to eq(:success)
        expect(result.verification_reset).to be true
        expect(result.warnings).to include(:verification_reset_failed, :verification_force_cleared)
        expect(trace).to include([:sql_status_update, 1], [:customer_verified_assigned, false])
      end

      it 'clears the row by id AND status, never by email (a sibling row must not move)' do
        op.call

        expect(accounts).to have_received(:where).with(id: 42, status_id: 2)
      end

      it 'records the forced clear under its own verb so the trail stays replayable' do
        op.call

        expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
          actor: 'cli',
          verb: 'customer.set_verification',
          target: 'ur_c',
          result: :success,
          detail: { verified: false, forced: true },
        )
      end

      it 'returns :verification_not_reset when the forced clear ALSO fails' do
        allow(by_id_verified).to receive(:update).and_raise(StandardError, 'db gone')

        result = op.call

        expect(result.status).to eq(:verification_not_reset)
        expect(result.verification_reset).to be false
        expect(result.warnings).to include(:verification_reset_failed, :verification_still_set)
      end

      it 'audits the change under the downgraded status, not :success' do
        allow(by_id_verified).to receive(:update).and_raise(StandardError, 'db gone')

        op.call

        expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
          hash_including(verb: 'customer.change_email', result: :verification_not_reset)
        )
      end

      it 'still reports the swap itself as applied' do
        allow(by_id_verified).to receive(:update).and_raise(StandardError, 'db gone')

        result = op.call

        expect(result.auth_row_updated).to be true
        expect(result.to).to eq(new_email)
      end

      # REGRESSION. SetVerification assigns `verified = false` in memory and
      # THEN saves (set_customer_verification.rb:112-116). When that save is
      # what raises, the in-memory predicate already reads false while the
      # datastore still holds 'true'. A fallback that guarded on
      # `@customer.verified?` would see false, skip the write, and report a
      # reset that never happened — in simple mode, where Redis IS the login
      # authority. The guard must read the persisted field.
      context 'and the in-memory flag was already flipped before the save blew up' do
        before { allow(customer).to receive(:verified?).and_return(false) }

        it 'still clears the PERSISTED flag rather than trusting memory' do
          op.call

          expect(trace).to include([:customer_verified_assigned, false])
        end

        it 'never reports a reset that did not reach the datastore' do
          # Only the SECOND save (the forced verification clear) blows up. The
          # first is the email commit — letting that one raise would produce
          # :partial and never exercise the fallback at all.
          saves = 0
          allow(customer).to receive(:save) do
            saves += 1
            trace << [:customer_save]
            raise StandardError, 'redis blip' if saves > 1

            true
          end
          allow(by_id_verified).to receive(:update).and_raise(StandardError, 'db gone')

          result = op.call

          expect(result.status).to eq(:verification_not_reset)
          expect(result.verification_reset).to be false
          expect(result.warnings).to include(:verification_still_set)
        end
      end

      # The mirror image: the field really is down in the datastore, so there is
      # nothing to force and no spurious forced-clear audit should be emitted.
      context 'and the datastore agrees the flag is already down' do
        before do
          allow(customer).to receive(:hget).with('verified').and_return('false')
          # ...and the accounts row is already Unverified, so the row-scoped,
          # status-conditional update matches nothing. Both stores agree.
          allow(by_id_verified).to receive(:update).and_return(0)
        end

        it 'does not record a forced clear it did not perform' do
          result = op.call

          expect(result.warnings).not_to include(:verification_force_cleared)
          expect(trace).not_to include([:customer_verified_assigned, false])
        end
      end
    end

    # SetVerification returns :no_change WITHOUT raising when the Redis mirror
    # already reads unverified — and it returns before touching SQL. If the
    # authoritative accounts row still says Verified, nothing was reset.
    context 'when the wrapper returns :no_change (no exception at all)' do
      before { allow(verifier).to receive(:call).and_return(:no_change) }

      it 'is a clean no-op when the accounts row already agrees' do
        account_status.replace(status_id: 1)

        result = op.call

        expect(result.status).to eq(:success)
        expect(result.verification_reset).to be true
        expect(result.warnings).to eq([])
        expect(trace).not_to include([:sql_status_update, 1])
      end

      it 'detects the mirror/SQL drift and force-clears the authoritative row' do
        account_status.replace(status_id: 2)

        result = op.call

        expect(result.status).to eq(:success)
        expect(result.warnings).to include(:verification_mirror_drift, :verification_force_cleared)
        expect(trace).to include([:sql_status_update, 1])
      end

      it 'fails CLOSED when the status probe itself cannot answer' do
        allow(by_id).to receive(:first).and_raise(StandardError, 'db down')

        result = op.call

        expect(result.warnings).to include(:verification_probe_failed)
        expect(trace).to include([:sql_status_update, 1])
      end
    end

    # SetCustomerVerification#update_rodauth_account! keys on `where(email:)`,
    # so with two rows sharing the address it would also move the CLOSED row
    # from 3 back to 1 — resurrecting a closed account.
    context 'when a sibling accounts row may share the address' do
      it 'bypasses the wrapper for closed-account reuse and clears row-scoped' do
        collision_rows.replace([{ id: 99, status_id: 3 }])

        result = op(allow_closed_account_reuse: true).call

        expect(Auth::Operations::Customers::SetVerification).not_to have_received(:new)
        expect(result.status).to eq(:success)
        expect(trace).to include([:sql_status_update, 1])
      end

      it 'bypasses the wrapper when the collision probe could not answer' do
        allow(by_email).to receive(:all).and_raise(StandardError, 'db down')

        result = op.call

        expect(Auth::Operations::Customers::SetVerification).not_to have_received(:new)
        expect(result.status).to eq(:success)
        expect(result.warnings).to include(:sql_collision_probe_failed)
      end
    end
  end

  # =========================================================================
  describe 'notifications (D36)' do
    it 'mails BOTH the old and the new address' do
      op.call

      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).twice
      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).with(
        :email_changed, hash_including(recipient: old_email), hash_including(fallback: :async_thread)
      )
      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).with(
        :email_changed, hash_including(recipient: new_email), hash_including(fallback: :async_thread)
      )
    end

    it 'sends nothing when notify is false (compromised-account remediation)' do
      op(notify: false).call

      expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email)
    end
  end

  # =========================================================================
  describe 'report-only warnings' do
    it 'warns when the NEW address is already suppressed' do
      allow(Onetime::EmailSuppression).to receive(:suppressed?).with(new_email).and_return(true)

      expect(op.call.warnings).to include(:new_address_suppressed)
    end

    it 'warns about pending invitations addressed to the OLD address, and never rewrites them' do
      org        = double('org', extid: 'og_i', identifier: 'og_i', is_default: 'false', contact_email: '')
      invitation = double('OrganizationMembership', :invited_email= => nil)
      allow(customer).to receive(:organization_instances).and_return([org])
      allow(Onetime::OrganizationMembership).to receive(:find_pending_by_email)
        .with(org, old_email).and_return(invitation)

      result = op.call

      expect(result.warnings).to include(:pending_invitations_orphaned)
      expect(invitation).not_to have_received(:invited_email=)
    end
  end

  # =========================================================================
  describe 'audit provenance (D41)' do
    it 'records --reason and --ticket in the audit detail when supplied' do
      op(reason: 'support request', ticket: 'ZD-9182').call

      expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
        hash_including(detail: hash_including(reason: 'support request', ticket: 'ZD-9182'))
      )
    end

    it 'omits them entirely when blank' do
      op(reason: '  ', ticket: nil).call

      detail = nil
      expect(Onetime::ColonelAuditEvent).to have_received(:record) { |kwargs| detail = kwargs[:detail] }
      expect(detail).not_to have_key(:reason)
      expect(detail).not_to have_key(:ticket)
    end
  end

  # =========================================================================
  describe 'simple mode (no auth database)' do
    before { allow(Auth::Database).to receive(:connection).and_return(nil) }

    # THE case the forced clear exists for. No accounts row means Redis alone
    # is the login authority, so a fallback that skipped its write here would
    # leave the account verified on an address nobody proved they own — while
    # reporting :success with verification_reset: true.
    context 'when the wrapper raised after flipping the flag in memory' do
      before do
        allow(verifier).to receive(:call).and_raise(StandardError, 'redis blip')
        allow(customer).to receive(:verified?).and_return(false)
        allow(customer).to receive(:hget).with('verified').and_return('true')
      end

      it 'clears the persisted flag even though memory already reads unverified' do
        op(db: nil).call

        expect(trace).to include([:customer_verified_assigned, false])
      end

      it 'reports the forced clear rather than a clean reset' do
        result = op(db: nil).call

        expect(result.warnings).to include(:verification_reset_failed, :verification_force_cleared)
      end
    end

    # Winning the HSETNX claim is a MUTATION (the old pre-write check was a pure
    # read). If the Redis phase then fails, the index entry points at a customer
    # that never took the address — so it is released rather than handed to the
    # operator as a doctor round-trip.
    context 'when the Redis phase fails after the claim was won' do
      before do
        allow(email_index).to receive(:hsetnx).and_return(true)
        allow(customer).to receive(:update_in_class_email_index).and_raise(StandardError, 'redis gone')
        # Allowed purely so the negative assertions below are well-formed — the
        # release must never route through the non-atomic HDEL wrapper.
        allow(email_index).to receive(:remove_field)
      end

      # The release MUST be compare-and-delete, not read-then-HDEL: winning the
      # HSETNX proves we took the field, not that we still hold it, and Familia's
      # auto-index on save is a blind HSET. A bare HDEL would therefore be able to
      # unindex a DIFFERENT, live account that claimed the address in between.
      it 'releases the claim by compare-and-delete on our own objid' do
        result = op(db: nil).call

        expect(index_dbclient).to have_received(:eval).with(
          described_class::RELEASE_INDEX_CLAIM_SCRIPT,
          keys: [index_dbkey],
          argv: [new_email, 'obj_c'],
        )
        expect(email_index).not_to have_received(:remove_field)
        expect(result.status).to eq(:partial)
        expect(result.warnings).not_to include(:email_index_claim_orphaned)
      end

      it 'falls back to :email_index_claim_orphaned when the release itself fails' do
        allow(index_dbclient).to receive(:eval).and_raise(StandardError, 'redis gone')

        result = op(db: nil).call

        expect(result.status).to eq(:partial)
        expect(result.warnings).to include(:email_index_claim_orphaned)
      end

      # 0 == the field no longer names us: someone else's blind HSET landed on
      # top of our claim, so the CAS correctly declines to delete THEIR live
      # entry. That is exactly the mismatch `customers doctor` reconciles, so it
      # must still warn — staying silent leaves that account unindexed with
      # nobody told to run it.
      it 'warns rather than deleting an entry that no longer names us' do
        allow(index_dbclient).to receive(:eval).and_return(0)

        result = op(db: nil).call

        expect(result.status).to eq(:partial)
        expect(result.warnings).to include(:email_index_claim_orphaned)
      end
    end

    it 'degrades to Redis-only and reports auth_row_updated: false, never a phantom success' do
      result = op(db: nil).call

      expect(result.status).to eq(:success)
      expect(result.auth_row_updated).to be false
      expect(trace).to eq(
        [
          [:customer_email_assigned, new_email],
          [:class_index_rekey, old_email],
          [:customer_save],
        ]
      )
    end

    # There is no SQL guard here, so the index entry is claimed with HSETNX:
    # the check and the write are one atomic operation, so a concurrent claim
    # can no longer be silently overwritten by us.
    it 'claims the index entry atomically rather than re-reading it' do
      expect(email_index).to receive(:hsetnx).with(new_email, 'obj_c').and_return(1)

      expect(op(db: nil).call.status).to eq(:success)
    end

    # The client boolifies HSETNX; the raw protocol answers 1/0. Both mean the
    # same thing and neither may be read as "someone else holds it".
    [1, true].each do |won|
      it "treats a #{won.inspect} reply as a won claim" do
        allow(email_index).to receive(:hsetnx).and_return(won)

        expect(op(db: nil).call.status).to eq(:success)
      end
    end

    [0, false].each do |lost|
      it "treats a #{lost.inspect} reply as a lost claim and aborts with :email_taken" do
        allow(email_index).to receive(:hsetnx).and_return(lost)
        allow(email_index).to receive(:get).with(new_email).and_return(nil, 'obj_other')

        result = op(db: nil).call

        expect(result.status).to eq(:email_taken)
        expect(customer).not_to have_received(:save)
      end
    end

    # A losing claim whose holder is US is pre-existing index drift, not a
    # collision — proceed and let the re-key repair it.
    it 'proceeds when the existing claim already points at the target customer' do
      allow(email_index).to receive(:hsetnx).and_return(false)
      allow(email_index).to receive(:get).with(new_email).and_return(nil, 'obj_c')

      expect(op(db: nil).call.status).to eq(:success)
    end

  end

  # =========================================================================
  # Full mode is serialized by the unique index on accounts.email, which every
  # writer passes through BEFORE its Redis write — no Redis-level claim needed,
  # and a lost race surfaces as the UniqueConstraintViolation covered above.
  # That guard is the ROW, though, not the connection.
  describe 'full mode: the claim follows the accounts row, not the connection' do
    it 'never touches the index claim when the customer has an accounts row' do
      op.call

      expect(email_index).not_to have_received(:hsetnx)
    end

    # A customer with no accounts row (a provisioning gap sync-auth-accounts
    # owns) updates nothing in step 1, so the unique constraint never fires.
    # Skipping the claim because a connection exists would leave that write with
    # no guard at all.
    it 'still claims the index entry when the accounts row is missing' do
      allow(by_external_id).to receive(:first).and_return(nil)
      expect(email_index).to receive(:hsetnx).with(new_email, 'obj_c').and_return(1)

      result = op.call

      expect(result.status).to eq(:success)
      expect(result.auth_row_updated).to be false
    end

    it 'aborts with :email_taken when that claim is lost' do
      allow(by_external_id).to receive(:first).and_return(nil)
      allow(email_index).to receive(:hsetnx).and_return(0)
      allow(email_index).to receive(:get).with(new_email).and_return(nil, 'obj_other')

      result = op.call

      expect(result.status).to eq(:email_taken)
      expect(customer).not_to have_received(:save)
    end
  end
end
