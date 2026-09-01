# lib/onetime/operations/org/delete.rb
#
# frozen_string_literal: true

# Loaded at the call site (CLI, the colonel endpoint, and the customer-facing
# organizations API), all of which run outside the app autoloaders — require the
# audit model explicitly.
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
# The member notification is enqueued from here, and the CLI reaches this file
# without the app's job wiring loaded (precedent:
# lib/onetime/logic/credential_change_session_revocation.rb).
require 'onetime/jobs/publisher'

module Onetime
  module Operations
    module Org
      # Permanently delete an organization — the SINGLE implementation of the
      # delete verb (#3731 P3, "one destroy path"), shared by every adapter:
      #
      #   - `bin/ots org delete ORG`
      #   - `DELETE /api/colonel/organizations/:org_id` (operator console)
      #   - `DELETE /api/organizations/:extid` (the org owner's own credentials,
      #     via OrganizationAPI::Logic::Organizations::DeleteOrganization)
      #
      # Before this op the teardown lived inside that last logic class, which the
      # shell cannot reach. The hand-run `bin/console` recipe that stood in for a
      # CLI therefore skipped three things the logic class does, and every skip
      # left the datastore dirtier than a no-op would have:
      # `Organization.instances` kept a dangling entry that `org doctor`,
      # `memberships` counting and the org list all walk; former members got no
      # `organization_deleted` mail; and nothing repointed `default_org_id`.
      #
      # ## Guardrails — statuses, not raises
      #
      # Every refusal RETURNS a {Result} whose `status` names the guard. Adapters
      # map that onto an exit code / form error. Evaluated in this order, first
      # trip wins:
      #
      #   :has_domains         domain_count > 0. Checked FIRST and never
      #                        overridable: `Organization#destroy!` raises
      #                        Onetime::Problem on domains, so without this the
      #                        operator gets a bare raise instead of the
      #                        `bin/ots domains remove` remediation — and the
      #                        raise would land AFTER the instances-zset removal
      #                        below, i.e. mid-teardown.
      #   :drifted_domains     domains that still name this org in
      #                        `CustomDomain.owners` but have fallen out of its
      #                        domains collection. These are invisible in the
      #                        owner's own domain list, so the remediation is
      #                        operator-side (`bin/ots domains doctor --all
      #                        --repair`), never a side effect of a delete.
      #                        Not overridable — `destroy!` raises on drift
      #                        for the same mid-teardown reason. See
      #                        #detect_domain_drift!.
      #   :is_default          the customer's default workspace. THE SERVER-SIDE
      #                        HALF OF A RULE THAT PREVIOUSLY EXISTED ONLY IN
      #                        VUE (see "The is_default hole" below).
      #                        Overridable with force_default.
      #   :active_subscription the subscription is still LIVE in Stripe —
      #                        `Organization#billing_live?`, which is wider than
      #                        `active_subscription?` on purpose: past_due and
      #                        unpaid orgs are delinquent, not gone, and recover
      #                        to active the moment a payment lands. NEVER calls
      #                        Stripe (out of scope, deliberately): deleting the
      #                        org while its subscription bills on is a support
      #                        incident, so the op refuses and the operator
      #                        cancels first. The refusal status keeps the
      #                        `:active_subscription` name because it is a wire
      #                        contract (CLI flag, API error key, UI payload).
      #                        Overridable with force_subscription.
      #   :last_org            the org's owner belongs to no other organization.
      #                        Deleting it strands them with no workspace, which
      #                        `OrganizationLoader` can only degrade around
      #                        (read-only phase, step 6). NOT overridable — the
      #                        remediation is to create the replacement org
      #                        first, or to purge the account outright with
      #                        `bin/ots customers purge-one`.
      #
      # ## The is_default hole this closes
      #
      # `Organization#can_delete?` refuses default workspaces and HAS NO CALLERS.
      # The customer-facing DeleteOrganization only ever checked
      # `require_entitlement_in!(org, 'manage_org')`, so the "contact us" flow the
      # UI promises for a default workspace was enforced by a Vue `v-if` alone: a
      # direct `DELETE /api/organizations/:extid` deleted an owner's default
      # workspace. Routing that adapter through this op fixes it by construction
      # — the customer-facing caller passes no force flags, so `:is_default`
      # refuses there unconditionally.
      #
      # ## Teardown order (mirrors the logic class this replaces, verbatim)
      #
      #   1. SNAPSHOT objid/extid/display_name and the member recipients
      #      ({email, locale}) — `list_members` is EMPTY once destroy! has run,
      #      so a snapshot taken afterwards notifies nobody.
      #   2. `Onetime::Organization.instances.remove(objid)` — the step the
      #      console recipe forgets. Familia v2 is `remove`, not `rem`.
      #   3. `org.destroy!` — members, pending invitations, contact_email_index.
      #   4. Clear `default_org_id` on every member pointing at the dead org.
      #   5. Enqueue `organization_deleted` per recipient, each isolated.
      #
      # Steps 4 and 5 run AFTER an irreversible destroy!, so neither may abort
      # the call: both isolate their failures and log. A missed step 4 degrades
      # to `bin/ots customers doctor --repair`; a missed step 5 costs an email.
      #
      # ## Audit — exactly one event, applied path only
      #
      # One {Onetime::ColonelAuditEvent} (`organization.delete`) per applied
      # delete, emitted HERE. Adapters MUST NOT audit; a self-auditing adapter
      # double-records.
      #
      # REFUSALS ARE DELIBERATELY NOT AUDITED — a documented divergence from
      # {Onetime::Operations::Org::TransferOwnership}, which records one
      # `result: :failure` per guardrail trip. That op is operator-only (CLI +
      # colonel). This one is also reachable by any authenticated org owner
      # through the customer-facing adapter, and the audit set is capped by COUNT
      # with no TTL (see {Onetime::ColonelAuditEvent}). Auditing refusals would
      # therefore hand every customer a log-eviction primitive: repeat
      # `DELETE /api/organizations/:extid` against your own default workspace and
      # each refusal evicts one real destructive-action record. Refusals are
      # logged (OT.info) instead. A raise mid-teardown still records one
      # `result: :failure` via {Onetime::AuditedFailure} — that path is not
      # customer-drivable, since every precondition a customer can trip returns a
      # status instead of raising.
      #
      # ## Constant-lookup discipline
      #
      # `Onetime::Operations::Billing` exists, so a bare constant inside this
      # namespace can resolve somewhere surprising and only intermittently.
      # Always fully qualify `Onetime::Organization` / `Onetime::Customer` here
      # (precedent: memberships/set_role.rb:64).
      class Delete
        include Onetime::AuditedFailure

        # Full-noun subject, matching the rest of the admin trail
        # (`organization.create`, `organization.reconcile`).
        AUDIT_VERB = 'organization.delete'

        # Statuses the adapters treat as "not a failure".
        OK_STATUSES = [:planned, :success].freeze

        # The complement: a delete was asked for and REFUSED by a guardrail.
        # Adapters exit non-zero / raise a form error on these.
        REFUSAL_STATUSES = [
          :has_domains,
          :drifted_domains,
          :is_default,
          :active_subscription,
          :last_org,
        ].freeze

        # A destructive verb whose teardown is irreversible from step 3 onward: a
        # delete that blows up partway leaves the org half-torn-down (instances
        # entry gone, record possibly still present), so the attempt must be in
        # the trail even though the success-path record never runs. Records one
        # `result: :failure` and re-raises.
        #
        # `dry_run` is in the detail because it defaults to TRUE here and the
        # success event is applied-path-only — without it an operator could not
        # tell a blown-up preview from a blown-up delete.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @extid },
          detail: -> { { dry_run: @dry_run } }

        # @!attribute status [r] Symbol — :planned (dry run) | :success | one of
        #   {REFUSAL_STATUSES}.
        # @!attribute org_id [r] String — the org's PUBLIC extid (never objid).
        # @!attribute display_name [r] String — snapshotted BEFORE destroy!.
        # @!attribute planid [r] String — the plan the org dies on, for the plan
        #   line of the operator's confirmation.
        # @!attribute members [r] Array<Hash> — `{ extid:, email: }` per member,
        #   snapshotted before teardown. The operator confirms against this.
        # @!attribute members_notified [r] Integer — `organization_deleted`
        #   messages successfully enqueued (applied path). On a refusal or a dry
        #   run this is the count that WOULD be notified, so the plan and the
        #   receipt read the same.
        # @!attribute pending_invitations [r] Integer — invitations destroy!
        #   cleans up.
        # @!attribute domain_count [r] Integer — size of the org's domains
        #   collection. THE GUARD'S INPUT, and deliberately not `domains.size`:
        #   `destroy!` raises on the raw count, while `list_domains` compacts
        #   away entries whose CustomDomain record is gone. A stale entry would
        #   otherwise pass this guard and blow up mid-teardown.
        # @!attribute domains [r] Array<String> — display domains still attached,
        #   for the remediation hint. SHORTER than `domain_count` when the
        #   collection carries drift; never longer.
        # @!attribute drifted_domains [r] Array<String> — display domains that
        #   still reference this org through `CustomDomain.owners` but are
        #   MISSING from its domains collection. Empty on the healthy path.
        #   Non-empty means `:drifted_domains`: the customer cannot see these
        #   in their domain list, so the remediation is operator-side
        #   (`bin/ots domains doctor --all --repair`).
        # @!attribute is_default [r] Boolean — the guard's input, echoed so an
        #   adapter can show WHY a delete was refused (or what force_default
        #   overrode).
        # @!attribute active_subscription [r] Boolean — same, for the billing
        #   guard.
        # @!attribute owner_id [r] String, nil — the owner's PUBLIC extid, or nil
        #   when `owner_id` resolved to no live customer (`org doctor` check 1).
        # @!attribute owner_org_count [r] Integer — organizations the owner
        #   belongs to, including this one. 0 when the owner is unresolvable.
        # @!attribute default_org_cleared [r] Array<String> — PUBLIC extids of
        #   customers whose `default_org_id` was cleared (on a dry run: that
        #   WOULD be cleared).
        # @!attribute dry_run [r] Boolean
        Result = Data.define(
          :status,
          :org_id,
          :display_name,
          :planid,
          # Deliberate shadow of Data#members: every surface of this feature —
          # the JSON payloads, the Zod schema, the admin UI — calls the org's
          # member snapshot `members`, and Data reflection is not part of this
          # Result's contract (adapters read fields by name, nothing enumerates
          # them).
          :members, # rubocop:disable Lint/DataDefineOverride
          :members_notified,
          :pending_invitations,
          :domain_count,
          :domains,
          :drifted_domains,
          :is_default,
          :active_subscription,
          :owner_id,
          :owner_org_count,
          :default_org_cleared,
          :dry_run,
        )

        # @param org [Onetime::Organization] resolved target (the adapter resolves).
        # @param actor [String, #extid, #email] acting principal's PUBLIC identity
        #   (colonel extid, the customer's own extid, or the CLI sentinel). Never
        #   an internal objid.
        # @param dry_run [Boolean] preview only when true (THE DEFAULT — same
        #   posture as Domains::Remove and Org::TransferOwnership).
        # @param force_default [Boolean] override the `:is_default` guard.
        #   OPERATOR SURFACES ONLY: the customer-facing adapter never passes it.
        # @param force_subscription [Boolean] override the `:active_subscription`
        #   guard. Cancels nothing — the subscription keeps billing.
        # @param deleted_by [String, nil] identity shown to former members in the
        #   `organization_deleted` mail. Defaults to the actor's public identity;
        #   the customer-facing adapter passes the acting customer's email so the
        #   notification reads the way it always has.
        def initialize(org:, actor:, dry_run: true, force_default: false,
                       force_subscription: false, deleted_by: nil)
          @org                = org
          @actor              = actor
          @dry_run            = dry_run
          @force_default      = force_default
          @force_subscription = force_subscription
          @deleted_by         = deleted_by

          # Snapshotted at construction so the AuditedFailure target survives a
          # raise anywhere in #call, including after destroy! has emptied the
          # in-memory record.
          @objid        = org.objid
          @extid        = org.extid
          @display_name = org.display_name
        end

        # @return [Result]
        # @raise [StandardError] only from a teardown step that fails outright;
        #   one `result: :failure` event is recorded first (AuditedFailure).
        def call
          # --- SNAPSHOT (before ANY mutation) ---
          # list_members is empty after destroy!, so everything the plan prints
          # and every recipient the notification needs is captured here, on both
          # the dry-run and the applied path.
          members       = @org.list_members
          @recipients   = build_recipients(members)
          @members      = members.map { |member| { extid: member.extid, email: member.email } }
          # Count and names are BOTH needed and are not interchangeable — see the
          # domain_count attribute doc.
          @domain_count = @org.domain_count.to_i
          @domains      = @org.list_domains.map(&:display_domain).compact
          @pending      = @org.pending_invitation_count
          @planid       = @org.planid.to_s

          # `is_default` is a conservative boolean: absent/blank means NOT
          # default (precedent: customers/change_email.rb:622). A bare truthiness
          # check would treat the string "false" as a default workspace.
          @is_default          = @org.is_default.to_s == 'true'
          @active_subscription = @org.billing_live?

          @owner                 = resolve_owner
          # The guard asks what the owner is left WITH, not how many rows they
          # have: an org they own but are not a member of (`org doctor` check 2)
          # would otherwise make a healthy two-org account look like a one-org
          # account, and vice versa.
          owner_orgs             = @owner ? @owner.organization_instances.to_a : []
          @owner_org_count       = owner_orgs.size
          @owner_other_org_count = owner_orgs.count { |candidate| candidate.objid.to_s != @objid.to_s }

          # Customers whose default_org_id points at this org. Only MEMBERS are
          # reachable without a full keyspace scan; a non-member pointing here is
          # already `bin/ots customers doctor` check 1 territory (it reports
          # "points to org customer is not a member of" today, before this op
          # runs at all).
          @default_org_holders = members.select { |member| member.default_org_id.to_s == @objid.to_s }

          detect_domain_drift!

          refusal = first_guardrail_trip
          return refuse(refusal) if refusal

          return build(:planned) if @dry_run

          apply!

          build(:success)
        end

        private

        # Detect domains that still name this org in `CustomDomain.owners` but
        # have fallen out of its domains collection. Detection ONLY — no path
        # through this op mutates on a refusal, so a preview and an applied run
        # report the same `:drifted_domains` for the same org.
        #
        # These domains are invisible in the owner's own domain list, so the
        # remediation is operator-side (`bin/ots domains doctor --all --repair`);
        # repairing index state as a side effect of a delete would be a
        # mutation on a path that promises to write nothing.
        def detect_domain_drift!
          @drifted = @org.unlisted_owned_domains
          return if @drifted.empty?

          OT.info "[Org::Delete] #{@extid} has #{@drifted.size} drifted domain(s): " \
                  "#{@drifted.map(&:display_domain).join(', ')} dry_run=#{@dry_run}"
        end

        # First guard to trip, or nil. Order matters: `:has_domains` is checked
        # ahead of everything because destroy! raises on it, and that raise would
        # land after the instances-zset removal.
        def first_guardrail_trip
          return :has_domains if @domain_count.positive?
          # Checked immediately after `:has_domains` for the same reason: these
          # are domains pointing at the org, and `Organization#destroy!` raises
          # on them too — a raise that would otherwise land after the
          # instances-zset removal.
          return :drifted_domains if @drifted.any?
          return :is_default if @is_default && !@force_default
          return :active_subscription if @active_subscription && !@force_subscription
          # Orphaned org (`org doctor` check 1): no owner_id and no owner
          # membership means no one to strand, so the guard has nothing to say.
          # A lookup that RAISED never reaches here — resolve_owner fails the
          # delete closed rather than reading an error as an orphan.
          return :last_org if @owner && @owner_other_org_count.zero?

          nil
        end

        # The irreversible half. Ordered exactly as the logic class this replaces
        # ordered it; see the teardown-order note in the class docs.
        def apply!
          # STEP 2 — the step the console recipe forgets. Familia v2 uses
          # `remove`, not `rem`. Done BEFORE destroy! so a crash cannot leave the
          # zset pointing at a destroyed record (the direction `org doctor`,
          # `memberships` counting and OrganizationsListCommand all walk).
          Onetime::Organization.instances.remove(@objid)

          # STEP 3 — members, pending invitations, contact_email_index.
          @org.destroy!

          OT.info "[Org::Delete] Deleted organization #{@extid} (#{@display_name}) " \
                  "members=#{@members.size} invitations=#{@pending}"

          # STEP 4 — the customer-row repair the console recipe leaves behind.
          @cleared = clear_default_org_pointers

          # STEP 5 — notify former members.
          @notified = notify_members_deleted

          # --- EXACTLY ONE audit event, applied path only ---
          # PUBLIC ids and counts only: member emails are operator-facing plan
          # output, not audit content.
          #
          # FAIL-CLOSED (#4333): the org, its memberships and its invitations
          # are gone by now, so there is nothing left to reconstruct the action
          # from. An unwritable event raises Onetime::AuditWriteFailure — the
          # adapter reports a failed delete instead of :success with no trail.
          # The teardown is NOT rolled back (see the model's fail-closed note);
          # the refusal statuses above still return normally and audit nothing.
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @extid,
            result: :success,
            detail: {
              display_name: @display_name.to_s,
              planid: @planid,
              members: @members.size,
              members_notified: @notified,
              pending_invitations: @pending,
              default_org_cleared: @cleared.size,
              forced: forced_guards,
            },
            fail_closed: true,
          )
        end

        # Owner memberships are the live authority (organization.rb:102-107 —
        # owner_id is the deprecated mirror), but the mirror is what `org doctor`
        # check 1 reads, so try it first and fall back rather than disagreeing
        # with the doctor about who the owner is.
        #
        # @return [Onetime::Customer, nil] nil on an orphaned org — no owner_id
        #   AND no owner membership. A lookup that RAISES is not an orphaned
        #   org: swallowing it to nil would read a transient datastore error as
        #   "nobody to strand" and wave the delete past the `:last_org` guard.
        #   A guard input that cannot be resolved fails the delete closed; the
        #   raise lands before any mutation and records one failure audit
        #   (audit_failures wraps #call).
        def resolve_owner
          owner_id = @org.owner_id.to_s
          owner    = owner_id.empty? ? nil : Onetime::Customer.load(owner_id)
          return owner if owner

          membership = Onetime::OrganizationMembership.active_for_org(@org).find(&:owner?)
          membership&.customer
        rescue StandardError => ex
          OT.le "[Org::Delete] owner resolution failed for #{@extid}: #{ex.class}: #{ex.message}"
          raise
        end

        # `{ email:, locale: }` per member with a usable address, snapshotted
        # BEFORE teardown.
        def build_recipients(members)
          members.filter_map do |member|
            email = member.email.to_s
            next if email.empty?

            { email: email, locale: member.respond_to?(:locale) ? member.locale : nil }
          end
        end

        # Clear `default_org_id` on every member pointing at the org we just
        # destroyed, so `bin/ots customers doctor` is clean immediately, with no
        # `--repair` pass. Matches the doctor's own repair (clear, don't guess a
        # replacement — OrganizationLoader re-derives one on the next request).
        #
        # destroy! has already committed, so a failure here is logged and
        # skipped: it degrades to the doctor finding it later, which is exactly
        # where we were before this op existed.
        #
        # @return [Array<String>] PUBLIC extids actually cleared.
        def clear_default_org_pointers
          @default_org_holders.filter_map do |customer|
            customer.default_org_id = nil
            customer.save
            OT.info "[Org::Delete] Cleared default_org_id for #{customer.extid} (org #{@extid} deleted)"
            customer.extid
          rescue StandardError => ex
            OT.le "[Org::Delete] Failed to clear default_org_id for #{customer.extid}: " \
                  "#{ex.class}: #{ex.message}"
            nil
          end
        end

        # Best-effort notification to former members. Each send is isolated so
        # one failure doesn't skip the rest, and no failure may affect the
        # (already-committed) deletion.
        #
        # @return [Integer] messages successfully enqueued.
        def notify_members_deleted
          @recipients.count do |recipient|
            # Blank ("") locales are truthy and slip past a bare `||`; treat as
            # missing.
            email_locale = recipient[:locale]
            email_locale = OT.default_locale if email_locale.to_s.strip.empty?

            Onetime::Jobs::Publisher.enqueue_email(
              :organization_deleted,
              {
                email_address: recipient[:email],
                organization_name: @display_name,
                deleted_by: deleted_by_label,
                deleted_at: Time.now.utc.iso8601,
                locale: email_locale,
              },
              fallback: :async_thread,
            )
            true
          rescue StandardError => ex
            OT.le "[Org::Delete] Failed to send organization_deleted email: #{ex.message}"
            false
          end
        end

        # OrganizationDeleted#validate_data! REQUIRES a non-nil deleted_by, so
        # this always resolves to something printable: the caller's override, the
        # actor's public identity, or the CLI/system sentinel behind it.
        def deleted_by_label
          label = @deleted_by.to_s
          return label unless label.empty?

          label = if @actor.respond_to?(:email) then @actor.email.to_s
                  elsif @actor.respond_to?(:extid) then @actor.extid.to_s
                  else @actor.to_s
                  end
          label.empty? ? 'system' : label
        end

        # Which overrides were exercised, for the audit detail. An operator
        # reading the trail must be able to see that a default workspace or a
        # billing org was deleted THROUGH a guard, not around one.
        def forced_guards
          forced = []
          forced << 'is_default' if @is_default && @force_default
          forced << 'active_subscription' if @active_subscription && @force_subscription
          forced
        end

        # Refusals write nothing and audit nothing (see the audit note in the
        # class docs — auditing them would be a log-eviction primitive on the
        # customer-facing adapter). They are logged so an operator can still
        # correlate a support report with a refusal.
        def refuse(status)
          OT.info "[Org::Delete] refused #{@extid} (#{@display_name}): #{status} dry_run=#{@dry_run}"
          build(status)
        end

        # Single exit point, so every status carries the same fully-populated
        # snapshot. `members_notified` / `default_org_cleared` report the applied
        # counts when there are any and the WOULD-BE counts otherwise, so a plan
        # and its receipt read alike.
        def build(status)
          Result.new(
            status: status,
            org_id: @extid,
            display_name: @display_name,
            planid: @planid,
            members: @members,
            members_notified: @notified || @recipients.size,
            pending_invitations: @pending,
            domain_count: @domain_count,
            domains: @domains,
            drifted_domains: @drifted.map(&:display_domain),
            is_default: @is_default,
            active_subscription: @active_subscription,
            owner_id: @owner&.extid,
            owner_org_count: @owner_org_count,
            default_org_cleared: @cleared || @default_org_holders.map(&:extid),
            dry_run: @dry_run,
          )
        end
      end
    end
  end
end
