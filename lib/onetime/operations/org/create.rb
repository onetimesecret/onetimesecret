# lib/onetime/operations/org/create.rb
#
# frozen_string_literal: true

# Loaded at the call site (CLI today, a colonel endpoint later), which run
# outside the app autoloaders — require the audit model explicitly.
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'

module Onetime
  module Operations
    module Org
      # Create an organization owned by an existing customer — the SINGLE
      # implementation of the admin create verb (#3731).
      #
      # Adapters:
      #   - `bin/ots org create NAME --owner OWNER`
      #   - (future) `POST /api/colonel/organizations` — there is no colonel
      #     create endpoint today; the two-phase shape below exists so adding one
      #     needs no second copy of the rules.
      #
      # ## Wrap, do not reimplement
      #
      # {Onetime::Organization.create!} already owns the hard part: the atomic
      # HSETNX contact_email reservation, the owner membership
      # (`role: 'owner'`), standalone entitlement materialization and the owner
      # membership materialization. This op adds exactly four things on top:
      # input normalization, the validation ruleset that until now lived only in
      # the customer-facing API logic class, the optional description write, and
      # the one admin audit event.
      #
      # POST-CONDITION: a `:created` org satisfies all five `bin/ots org doctor`
      # invariants (owner_id resolves; owner is in the members set; every member
      # has a backing object; the only `role: 'owner'` membership is the
      # owner_id; at least one member). Asserted against a real datastore in
      # spec/unit/onetime/operations/org/create_spec.rb.
      #
      # ## Two entry points, one validation
      #
      # {#validate} is the pure, side-effect-free half (normalize + reject); it
      # performs no writes and no audit. {#call} re-runs it (cheap: string ops
      # plus one index read) so no caller can skip it. Same shape as
      # {Onetime::Operations::Domains::Create}.
      #
      # ## Audit (CONTRACT 4)
      #
      # Exactly ONE {Onetime::ColonelAuditEvent} per successful create, emitted
      # here. Adapters MUST NOT audit. Every rejection mutates nothing and
      # audits nothing.
      #
      # ## Deliberate omissions — read these before "fixing" them
      #
      # - NO org-count quota and NO `Familia::Lock`. The quota
      #   (`CreateOrganization#check_organization_quota!`) is a customer-plan
      #   limit; an operator create is an admin verb that deliberately bypasses
      #   it, exactly as {Onetime::Operations::Domains::Create} carries no
      #   membership/entitlement gate. The lock exists only to close the quota
      #   TOCTOU, so with no quota there is nothing left for it to guard —
      #   concurrent same-email creates are already made safe by the HSETNX
      #   reservation inside `create!`.
      # - NO `--plan` (D22). Assigning a plan would make this `lib/` op depend on
      #   the billing app. The operator runs `bin/ots org reconcile` afterwards.
      # - NO `is_default` (D24). `is_default: true` makes the org UNDELETABLE
      #   (`Organization#can_delete?`) and interacts with the domain-SSO archive
      #   path; a one-way undeletable flag behind a plain `--yes` is wrong.
      #   Signup (`CreateDefaultWorkspace`) owns `is_default`.
      # - NO `default_org_id` write (D23) — that is customer-scoped state, not
      #   org state.
      # - NO orphan adoption. `CreateDefaultWorkspace` adopts an existing
      #   zero-member org found via the contact_email index; that is signup
      #   RECOVERY behaviour. For an operator create verb, adopting a stranger's
      #   org is wrong — a taken email is a rejection here.
      # - `created_by` is never settable (D25). `create!` stamps it to the owner
      #   and it is immutable audit state (ADR-012). There is no "create on
      #   behalf of X but attribute it to Y".
      #
      # ## Constant-lookup discipline
      #
      # `Onetime::Operations::Billing` exists, so a bare constant inside this
      # namespace can resolve somewhere surprising and only intermittently
      # (depending on what else got loaded). Always fully qualify
      # `Onetime::Organization` / `Onetime::Customer` /
      # `Onetime::OrganizationMembership` here (precedent:
      # memberships/set_role.rb:64).
      class Create
        include Onetime::AuditedFailure

        AUDIT_VERB = 'organization.create'

        # Field limits. SINGLE source of truth for BOTH create surfaces: the
        # customer-facing OrganizationAPI::Logic::Organizations::CreateOrganization
        # aliases these constants (D21, #3907). Signup deliberately still does
        # NOT route through this op — that would flood the capped admin audit
        # set — it shares only the limits.
        MAX_DISPLAY_NAME = 100
        MAX_DESCRIPTION  = 500

        # Rejection reasons -> the operator-facing message. Adapters render these
        # verbatim so the CLI and a future colonel endpoint cannot drift.
        REJECTIONS = {
          missing_owner: 'Owner is required',
          anonymous_owner: 'Cannot create an organization owned by an anonymous customer',
          blank_name: 'Display name is required',
          name_too_long: "Display name must be #{MAX_DISPLAY_NAME} characters or fewer",
          description_too_long: "Description must be #{MAX_DESCRIPTION} characters or fewer",
          # Byte-identical to the message Organization.create! raises when the
          # HSETNX reservation loses the race, so the pre-check and the race
          # report the same thing.
          email_taken: 'Organization exists for that email address',
        }.freeze

        # Every rejection is a REFUSED privileged create, so each records one
        # `result: :failure` event. Derived from REJECTIONS so a new rejection
        # reason cannot silently escape the trail.
        REFUSAL_STATUSES = REJECTIONS.keys.freeze

        # TARGET DEVIATION, READ THIS BEFORE CHANGING IT: the success event's
        # target is `org.extid` (an `on_*` id), but on the failure path the org
        # does NOT EXIST — it was never created, or `create!` blew up. There is
        # no `@org` ivar to read, and a lambda reading one would land silently as
        # 'unknown' (AuditedFailure.resolve rescues). So a failed create targets
        # the OWNER's extid (`ur_*`), the only stable PUBLIC id in play, and the
        # detail carries the requested display_name. Filtering by verb finds
        # these; filtering by an org id cannot, because there is no org id.
        #
        # create! reserves contact_email via HSETNX and writes several fields;
        # anything other than the uniqueness race re-raises (see #create_org),
        # and the success record sits after all of it.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @owner&.extid },
          detail: -> { { owner_id: @owner&.extid, display_name: @display_name_input.to_s.strip } }

        # Outcome of {#validate}.
        #
        # @!attribute status [r] Symbol — :ok, or one of {REJECTIONS}' keys.
        # @!attribute display_name [r] String, nil — stripped name when :ok.
        # @!attribute description [r] String, nil — stripped description, or nil.
        # @!attribute contact_email [r] String, nil — normalized email, or nil.
        # @!attribute message [r] String, nil — operator-facing rejection text.
        Check = Data.define(:status, :display_name, :description, :contact_email, :message)

        # Outcome of {#call}.
        #
        # @!attribute status [r] Symbol — :created, or a rejection key.
        # @!attribute org_id [r] String, nil — the org's PUBLIC id (extid).
        # @!attribute objid [r] String, nil — the org's internal id. Carried
        #   ONLY because `bin/ots org doctor` prints both and an operator needs
        #   to correlate the two; it is never put in the audit record.
        # @!attribute display_name [r] String, nil
        # @!attribute owner_id [r] String, nil — the owner's PUBLIC extid (NOT
        #   the objid written to `org.owner_id`).
        # @!attribute contact_email [r] String, nil
        # @!attribute message [r] String, nil — rejection text.
        Result = Data.define(
          :status,
          :org_id,
          :objid,
          :display_name,
          :owner_id,
          :contact_email,
          :message,
        )

        # @param display_name [String] raw operator input.
        # @param owner [Onetime::Customer] resolved owner (the adapter resolves;
        #   NEVER fabricate one — ADR-023 real, not synthesized).
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid, or the CLI sentinel). Never an internal objid.
        # @param contact_email [String, nil] optional unique billing/contact
        #   address.
        # @param description [String, nil] optional description.
        def initialize(display_name:, owner:, actor:, contact_email: nil, description: nil)
          @display_name_input  = display_name
          @owner               = owner
          @actor               = actor
          @contact_email_input = contact_email
          @description_input   = description
        end

        # Pure validation + normalization. No writes, no audit. Safe to call
        # from an HTTP adapter's raise_concerns.
        #
        # @return [Check]
        def validate
          return reject(:missing_owner) if @owner.nil?
          return reject(:anonymous_owner) if @owner.anonymous?

          display_name = @display_name_input.to_s.strip
          return reject(:blank_name) if display_name.empty?
          return reject(:name_too_long) if display_name.length > MAX_DISPLAY_NAME

          description = @description_input.to_s.strip
          description = nil if description.empty?
          return reject(:description_too_long) if description && description.length > MAX_DESCRIPTION

          contact_email = OT::Utils.normalize_email(@contact_email_input.to_s)
          contact_email = nil if contact_email.empty?
          # Pre-check for a precise message only. The real guard is the HSETNX
          # inside create! (see the rescue in #call) — this read can go stale
          # between here and the write.
          return reject(:email_taken) if contact_email && Onetime::Organization.contact_email_exists?(contact_email)

          Check.new(
            status: :ok,
            display_name: display_name,
            description: description,
            contact_email: contact_email,
            message: nil,
          )
        end

        # @return [Result]
        def call
          check = validate
          return rejected_result(check) unless check.status == :ok

          org = create_org(check)
          return rejected_result(reject(:email_taken)) if org.nil?

          normalize_owner_id!(org)
          apply_description(org, check.description)

          # Exactly one audit event per successful create. PUBLIC ids only —
          # never objid/custid.
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: org.extid,
            result: :success,
            detail: {
              display_name: org.display_name,
              owner_id: @owner.extid,
            },
          )

          OT.info "[Org::Create] #{org.extid} owner=#{@owner.extid} name=#{org.display_name}"

          Result.new(
            status: :created,
            org_id: org.extid,
            objid: org.objid,
            display_name: org.display_name,
            owner_id: @owner.extid,
            contact_email: check.contact_email,
            message: nil,
          )
        end

        private

        # @return [Onetime::Organization, nil] nil when the contact_email
        #   reservation lost the race (rendered as :email_taken).
        def create_org(check)
          Onetime::Organization.create!(check.display_name, @owner, check.contact_email)
        rescue Onetime::Problem => ex
          # The HSETNX guard inside create! is the authoritative uniqueness
          # check; #validate's pre-check exists only for the message. Anything
          # else is a real failure and must not be swallowed into a rejection.
          raise unless ex.message.to_s.include?('Organization exists')

          nil
        end

        # D31: `org.owner_id` must hold the owner's OBJID — that is what
        # `bin/ots org doctor` compares against (`Customer.load(org.owner_id)`
        # and the members-set entries, which are objid-keyed).
        #
        # `Organization.create!` writes the objid itself as of #3907, so this
        # is a no-op write-wise today (the guard below). It stays as a
        # belt-and-braces assertion of the op's post-condition — the doctor
        # invariants hold even if a future `create!` change regresses the
        # owner_id space. Do not "simplify" it away.
        def normalize_owner_id!(org)
          desired = @owner.objid.to_s
          return if desired.empty?
          return if org.owner_id.to_s == desired

          org.owner_id = desired
          org.save
        end

        def apply_description(org, description)
          return if description.nil?

          org.description = description
          org.save
        end

        def reject(status)
          Check.new(
            status: status,
            display_name: nil,
            description: nil,
            contact_email: nil,
            message: REJECTIONS.fetch(status),
          )
        end

        # Same verb/actor as the success event; see the TARGET DEVIATION note on
        # audit_failures for why the target is the owner rather than the org.
        # Best-effort: never break the op.
        def record_refusal(check)
          owner_extid = @owner&.extid.to_s
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            # :missing_owner has no owner to name. Use the SAME sentinel the
            # macro's resolver falls back to, so the two failure paths agree.
            target: owner_extid.empty? ? Onetime::AuditedFailure::UNKNOWN : owner_extid,
            result: :failure,
            detail: {
              reason: check.status.to_s,
              owner_id: @owner&.extid,
              display_name: @display_name_input.to_s.strip,
            },
          )
        rescue StandardError => ex
          OT.le "[Org::Create] refusal audit failed: #{ex.class}: #{ex.message}"
        end

        # Single exit point for every rejection (#validate's and the create!
        # race's), so the refusal audit cannot be forgotten at either.
        def rejected_result(check)
          record_refusal(check) if REFUSAL_STATUSES.include?(check.status)

          Result.new(
            status: check.status,
            org_id: nil,
            objid: nil,
            display_name: nil,
            owner_id: nil,
            contact_email: nil,
            message: check.message,
          )
        end
      end
    end
  end
end
