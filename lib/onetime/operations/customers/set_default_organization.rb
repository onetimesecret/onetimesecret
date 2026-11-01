# lib/onetime/operations/customers/set_default_organization.rb
#
# frozen_string_literal: true

# Loaded at the call site (colonel logic + CLI), which run outside the app
# autoloaders — require the audit model and the shared envelopes explicitly.
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/audit_reason'
require 'onetime/operations/audit_attempt'
require 'onetime/application/organization_loader'

module Onetime
  module Operations
    module Customers
      # Set a customer's default organization (customer.default_org_id) on an
      # operator's behalf — the SINGLE implementation of the verb. The colonel
      # endpoint (`POST /api/colonel/users/:user_id/default-organization`) and
      # `bin/ots customers set-default-org` are thin adapters over it.
      #
      # The customer-facing twin is AccountAPI::Logic::Account::UpdateDefaultOrganization,
      # which also selects the organization for the caller's own session. An
      # operator has no session of the customer's to select in, so this op
      # writes the preference only; OrganizationLoader honours it on the
      # customer's next request that no header, session selection or custom
      # domain decides.
      #
      # ## Which organizations may be chosen
      #
      # Only one the customer already belongs to, on every record that says
      # so: an ACTIVE OrganizationMembership (a pending invitation is not
      # membership), the organization's member set, and the customer's own
      # organization list. The last is the one OrganizationLoader picks the
      # default from (Onetime::MembershipSnapshot#organizations, i.e.
      # customer.organization_instances), so an organization missing from it
      # is refused as :not_member rather than written as a preference the
      # loader would ignore. The organization must also not be archived (the
      # loader skips archived ones). An operator cannot use this verb to give
      # a customer access to anything: membership is AddMembership's job.
      #
      # ## Audit (CONTRACT 4: the op owns the event)
      #
      # One event per call, verb `customer.set_default_org`, target the
      # customer's extid, `org_id` the organization's extid:
      #
      #   applied   -> .record, result: :success, detail { from, to, org_id }
      #                (+ reason). Not fail-closed: a landing preference grants
      #                no capability and the same verb restores it, so a lost
      #                event does not justify failing the change (the
      #                "corrective" family in ColonelAuditEvent.record).
      #   no change -> the #4337 no-change attempt (`outcome: 'no_change'`).
      #   dry run   -> the #4337 preview observation; nothing is written.
      #   refusal   -> .record, result: :failure, detail { reason: <status>,
      #                org_id } (+ dry_run). Fail-open, and without the
      #                operator reason, as in Memberships::SetRole.
      #   raise     -> one failure event via {Onetime::AuditedFailure}.
      #
      # `from` / `to` are organization extids. `from` is the EFFECTIVE default
      # before the change (OrganizationLoader.default_organization), which can
      # equal `to` when the stored preference was empty or stale and the
      # fallback already landed the customer here; the write then pins it.
      class SetDefaultOrganization
        include Onetime::AuditedFailure
        include Onetime::AuditReason
        include Onetime::Operations::AuditAttempt

        AUDIT_VERB = 'customer.set_default_org'

        # Statuses meaning "a change was asked for and refused". Each records
        # one `result: :failure` event via {#build}.
        REFUSAL_STATUSES = [:anonymous, :not_member, :archived].freeze

        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @customer&.extid }

        # @!attribute status [r] Symbol —
        #   :success | :no_change | :dry_run | :anonymous | :not_member | :archived
        # @!attribute previous [r] Onetime::Organization, nil — the effective
        #   default before this call (nil when there was none)
        Result = Data.define(:status, :customer, :organization, :previous, :dry_run) do
          def success? = status == :success
          def no_change? = status == :no_change
          def refused? = REFUSAL_STATUSES.include?(status)
        end

        # @param customer [Onetime::Customer] whose default changes (caller resolves).
        # @param organization [Onetime::Organization] the new default (caller resolves).
        # @param actor [String] acting admin's PUBLIC identity (colonel extid, or
        #   the CLI sentinel Onetime::CLI::Customers::Shared::CLI_ACTOR). Never
        #   an internal objid.
        # @param reason [String, nil] OPTIONAL operator-supplied why (#4338).
        # @param dry_run [Boolean] check eligibility and report, write nothing.
        def initialize(customer:, organization:, actor:, reason: nil, dry_run: false)
          @customer     = customer
          @organization = organization
          @actor        = actor
          @reason       = normalize_reason(reason)
          @dry_run      = dry_run ? true : false
        end

        # @return [Result]
        def call
          return build(:anonymous) if @customer.anonymous?
          return build(:not_member) unless active_member?
          return build(:archived) if @organization.archived?

          @previous = Onetime::Application::OrganizationLoader.default_organization(@customer)

          # Already the stored preference: nothing to write. Recorded by
          # intent (#4337): a live call as a no-change attempt, a dry run as
          # a preview.
          if @customer.default_org_id.to_s == @organization.objid.to_s
            if @dry_run
              record_preview_observation(with_reason(change_detail.merge(outcome: NO_CHANGE_OUTCOME)))
            else
              record_no_change_attempt(with_reason(change_detail))
            end
            return build(:no_change)
          end

          if @dry_run
            record_preview_observation(with_reason(change_detail))
            return build(:dry_run)
          end

          # Single-field write; the fast writer also drops the request's
          # membership snapshot (Customer::MembershipSnapshotHooks).
          @customer.default_org_id!(@organization.objid)

          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: with_reason(change_detail),
          )

          build(:success)
        end

        private

        def audit_target = @customer.extid

        def active_member?
          membership = Onetime::OrganizationMembership.find_by_org_customer(
            @organization.objid, @customer.objid
          )
          return false unless membership&.active?
          return false unless @organization.member?(@customer)

          listed_for_customer?
        end

        # The list OrganizationLoader#choose_default reads.
        def listed_for_customer?
          Onetime::MembershipSnapshot.for(@customer).organizations.any? do |org|
            org.objid.to_s == @organization.objid.to_s
          end
        end

        def change_detail
          { from: @previous&.extid, to: @organization.extid, org_id: @organization.extid }
        end

        def build(status)
          record_refusal(status) if REFUSAL_STATUSES.include?(status)

          Result.new(
            status: status,
            customer: @customer,
            organization: @organization,
            previous: @previous,
            dry_run: @dry_run,
          )
        end

        # Best-effort like every refusal audit: never break the op.
        def record_refusal(status)
          detail           = { reason: status.to_s, org_id: @organization.extid }
          detail[:dry_run] = true if @dry_run

          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :failure,
            detail: detail,
          )
        rescue StandardError => ex
          OT.le "[Customers::SetDefaultOrganization] refusal audit failed: #{ex.class}: #{ex.message}"
        end
      end
    end
  end
end
