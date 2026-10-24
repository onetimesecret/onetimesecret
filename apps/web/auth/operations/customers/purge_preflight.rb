# apps/web/auth/operations/customers/purge_preflight.rb
#
# frozen_string_literal: true

require 'auth/operations/customers/registry_sweep'

module Auth
  module Operations
    module Customers
      # Read-only, drift-tolerant organization preflight for an administrative
      # customer purge. A plan is executable only when every discovered
      # relationship is complete and unambiguous.
      # rubocop:disable Metrics/ClassLength -- one blocker taxonomy; splitting it
      # would scatter the refusal rules across files
      class PurgePreflight
        # Historical identifiers and billing contacts are removed by the canonical
        # organization destroy, not scrubbed before preflight. Unknown subscription
        # state and outstanding replacement-checkout intent still need resolution.
        NON_LIVE_SUBSCRIPTION_STATUSES = %w[canceled incomplete incomplete_expired paused].freeze
        BILLING_MIGRATION_FIELDS       = [
          :pending_currency_migration,
          :migration_target_price_id,
          :migration_effective_after,
        ].freeze

        # Workspace content that belongs to the departing account. It is deleted
        # WITH the organization, so its presence is not a reason to refuse an
        # erasure request; it is reported as evidence only.
        RETAINED_SCALAR_FIELDS = [
          :description,
          :archived_at,
          :archived_comment,
        ].freeze

        class Action
          attr_reader :type, :organization, :org_id, :role, :notes, :account_purge_context, :reference

          def initialize(type:, organization:, org_id:, role:, notes: [], account_purge_context: nil, reference: nil)
            @reference             = reference
            @type                  = type
            @organization          = organization
            @org_id                = org_id
            @role                  = role
            @notes                 = notes.freeze
            @account_purge_context = account_purge_context
            freeze
          end

          # `notes` are evidence, never a refusal reason, so they are deliberately
          # NOT part of the plan signature: data the purge is about to delete must
          # not change under a concurrent write and invalidate an in-flight plan.
          def public_detail(status: :planned)
            detail             = { type: type, org_id: org_id, role: role, status: status }
            detail[:reference] = reference if type == :remove_stale_participation
            notes.empty? ? detail : detail.merge(notes: notes)
          end
        end

        Plan = Data.define(:actions, :blockers) do
          def executable? = blockers.empty?

          def signature
            [
              actions.map do |action|
                              entry = [action.type, action.organization.objid.to_s, action.role.to_s]
                              entry << action.reference if action.type == :remove_stale_participation
                              entry
              end.sort,
              blockers.map { |blocker| blocker.sort_by { |key, _value| key.to_s } }.sort_by(&:to_s),
            ]
          end

          def action_details(status: :planned)
            actions.map { |action| action.public_detail(status: status) }
          end
        end

        # An opaque, internal capability used only by Org::Delete. Authorization
        # performs a fresh complete preflight and requires the exact plan that
        # produced the capability, so merely supplying the target customer cannot
        # bypass the default/last-org guardrails.
        class AccountPurgeContext
          attr_reader :customer_objid

          def initialize(customer:, organization_objid:, plan_signature:, deep: false,
                         membership_snapshot: nil, registry_sweep: nil)
            @customer             = customer
            @customer_objid       = customer.objid.to_s
            @organization_objid   = organization_objid.to_s
            @plan_signature       = plan_signature
            @deep                 = deep
            @membership_snapshot  = membership_snapshot
            @registry_sweep       = registry_sweep
          end

          def authorized_for?(organization)
            return false unless organization.objid.to_s == @organization_objid

            plan = PurgePreflight.new(
              customer: @customer,
              deep: @deep,
              membership_snapshot: @membership_snapshot,
              registry_sweep: @registry_sweep,
            ).call
            return false unless plan.executable? && plan.signature == @plan_signature

            plan.actions.any? do |action|
              action.type == :delete_organization &&
                action.organization.objid.to_s == @organization_objid
            end
          rescue StandardError
            false
          end
        end

        # @param customer [Onetime::Customer] purge target
        # @param deep [Boolean] when true, discovery additionally sweeps the
        #   GLOBAL Organization, OrganizationMembership and CustomDomain
        #   registries. That catches references no reverse index points at
        #   (an org whose `owner_id` names the customer but which is absent from
        #   their participations). The sweep is a {RegistrySweep}: pipelined
        #   field reads over every registry row, captured once per preflight
        #   unless the caller hands one in. `Purge` re-runs preflight once per
        #   action plus three teardown revalidations, so deep discovery is
        #   reserved for operator sweeps and is never used on a request path.
        #   Shallow discovery reaches the same organizations through the
        #   customer's own reverse indexes (participations,
        #   organization_instances, default_org_id and the contact-email claim)
        #   and keeps every per-organization drift check.
        # @param registry_sweep [RegistrySweep, nil] the registries as an
        #   earlier deep preflight of the same purge listed them. The sweep
        #   holds identifiers only: every organization, membership row and
        #   domain it points at is re-loaded here, so the evidence is live and
        #   only the WHERE-TO-LOOK is reused. Ignored unless `deep` is true.
        # @param membership_snapshot [MembershipSnapshot, nil] membership objids
        #   grouped by organization, captured ONCE by a bulk run. Shallow
        #   discovery otherwise derives an organization's rows from its own
        #   `members` set, so a live row whose customer fell out of that set is
        #   invisible and the workspace can read as sole-owned. The snapshot
        #   closes that gap for every candidate of a sweep at the cost of one
        #   registry read per run instead of one per preflight.
        attr_reader :pending_organization_checks, :registry_sweep

        def initialize(customer:, deep: false, membership_snapshot: nil, registry_sweep: nil)
          @customer                    = customer
          @deep                        = deep
          @membership_snapshot         = membership_snapshot
          @registry_sweep              = deep ? registry_sweep : nil
          @registered_org_ids          = {}
          @blockers                    = []
          @organizations               = {}
          @participation_ids           = []
          @stale_participation_actions = []
          @pending_organization_checks = []
          @orphan_dependency_blockers  = {}
          @instance_ids                = []
          @email_holder_id             = nil
          @active_memberships_by_org   = Hash.new { |hash, key| hash[key] = [] }
          @pending_memberships_by_org  = Hash.new { |hash, key| hash[key] = [] }
          @retained_memberships_by_org = Hash.new { |hash, key| hash[key] = [] }
        end

        # @return [Plan]
        def call
          add_blocker(:migration_in_flight) if migration_in_flight?(@customer)
          # The sweep is captured once per preflight unless the caller supplied
          # one. A registry that could not be listed is reported by the
          # discovery step that depends on it, so the blocker codes match the
          # per-row walk this replaced.
          @registry_sweep ||= RegistrySweep.capture(customer_objid: customer_objid) if @deep
          discover_participations
          check_pending_organization_purges
          discover_contact_email_holder
          discover_instances
          discover_memberships
          check_domain_scan if @deep

          actions = (@organizations.values.filter_map { |org| classify(org) } + @stale_participation_actions)
            .sort_by { |action| [action.organization.objid.to_s, action.type.to_s, action.reference.to_s] }
          plan    = Plan.new(actions: actions, blockers: sorted_blockers)

          attach_account_purge_contexts(plan)
        rescue StandardError => ex
          add_blocker(:preflight_incomplete, message: ex.class.name)
          Plan.new(actions: [], blockers: sorted_blockers)
        end

        # Recheck retained cleanup actions even after their participation (or the
        # customer itself) has been deleted. Share evidence only within this
        # checker; every preflight after a mutation must use a fresh checker.
        def stale_participation_blockers(action)
          blockers = orphan_dependency_blockers(action.organization)
          return [] if blockers.empty?

          [{ code: :dangling_customer_participation, reference: action.reference }] + blockers
        end

        private

        # Markers outlive reverse-index removal, so a fresh purge must inspect
        # them even when discovery no longer has a relationship to follow. They
        # authorize no cleanup action and remain until the customer is destroyed.
        def check_pending_organization_purges
          @customer.purge_pending_organization_checks.to_a.sort_by(&:to_s).each do |reference|
            objid = reference.is_a?(String) ? organization_id_from_participation(reference) : nil
            unless valid_purge_organization_id?(objid)
              add_blocker(:invalid_purge_pending_organization_check, reference: reference.to_s)
              next
            end

            action = Action.new(
              type: :remove_stale_participation,
              organization: Onetime::Organization.new(objid: objid),
              org_id: objid,
              role: '',
              reference: reference,
            )
            @pending_organization_checks << action
            stale_participation_blockers(action).each do |blocker|
              add_blocker(blocker.fetch(:code), **blocker.reject { |key, _| key == :code })
            end
          end
        rescue StandardError => ex
          add_blocker(:purge_pending_organization_checks_lookup_failed, message: ex.class.name)
        end

        def discover_participations
          raw_keys           = @customer.participations.to_a.map(&:to_s)
          @participation_ids = raw_keys.filter_map { |key| organization_id_from_participation(key) }.uniq

          @participation_ids.each do |objid|
            org = Onetime::Organization.load(objid)
            if org
              add_organization(org)
            else
              references = raw_keys.select { |key| organization_id_from_participation(key) == objid }.uniq.sort
              discover_stale_participations(objid, references)
            end
          end

          # Keep the generated projection in the union. It is existence-checked,
          # while the raw participation set above exposes dangling references.
          @customer.organization_instances.to_a.each { |org| add_organization(org) }

          # The customer's own pointer is a reverse index in its own right: a
          # default workspace whose membership rows drifted is still reachable.
          # Discovery only: a pointer left over from an organization that is
          # already gone is not drift worth refusing over, and it dangles by
          # design between the cleanup and teardown stages of a purge.
          default_org_id = @customer.default_org_id.to_s
          unless default_org_id.empty?
            org = Onetime::Organization.load(default_org_id)
            add_organization(org) if org
          end
        rescue StandardError => ex
          add_blocker(:participation_lookup_failed, message: ex.class.name)
        end

        # Only the orphan path pays for these scans. An absent object hash alone
        # does not prove teardown completed: through-model keys wrap a composite
        # objid, and invitations/domains can survive without their reverse indexes.
        def discover_stale_participations(objid, references)
          unless valid_purge_organization_id?(objid)
            references.each { |reference| add_blocker(:dangling_customer_participation, reference: reference) }
            return
          end

          org = Onetime::Organization.new(objid: objid)
          references.each do |reference|
            action   = Action.new(
              type: :remove_stale_participation,
              organization: org,
              org_id: objid,
              role: '',
              reference: reference,
            )
            blockers = stale_participation_blockers(action)
            if blockers.empty?
              @stale_participation_actions << action
            else
              blockers.each { |blocker| add_blocker(blocker.fetch(:code), **blocker.reject { |key, _| key == :code }) }
            end
          end
        end

        # Cache only organization evidence, never reference-specific blockers.
        # Read failures are evidence too: aliases must all fail closed together.
        def orphan_dependency_blockers(org)
          org_id = org.objid.to_s
          @orphan_dependency_blockers.fetch(org_id) do
            @orphan_dependency_blockers[org_id] = if orphan_dependencies?(org)
                                                  [{ code: :orphan_organization_dependencies_remain, org_id: org_id }]
                                                else
                                                  []
                                                end
          end
        rescue StandardError => ex
          @orphan_dependency_blockers[org_id] = [
            { code: :organization_evidence_incomplete, org_id: org_id, message: ex.class.name },
          ]
        end

        def orphan_dependencies?(org)
          objid = org.objid.to_s
          return true if Onetime::Organization.load(objid)
          return true if Onetime::Organization.instances.member?(org)

          %w[organization org].each do |prefix|
            return true if Onetime::Organization.dbclient.scan_each(match: "#{prefix}:*")
              .any? { |key| key.start_with?("#{prefix}:#{objid}:") }
          end
          [:contact_email_index, :extid_lookup, :stripe_customer_id_index, :stripe_subscription_id_index].each do |index|
            return true if Onetime::Organization.public_send(index).hgetall.values.any? { |id| id.to_s == objid }
          end

          membership_class = Onetime::OrganizationMembership
          membership_ids   = []
          membership_class.dbclient.scan_each(match: "#{membership_class.prefix}:*").each do |key|
            # Include subkeys even when the membership object has already gone.
            return true if %w[organization org].any? do |prefix|
              key.start_with?("#{membership_class.prefix}:#{prefix}:#{objid}:")
            end

            if key.end_with?(':object')
              membership_ids << key.delete_prefix("#{membership_class.prefix}:").delete_suffix(':object')
            end
          end
          membership_class.instances.each { |id| membership_ids << id.to_s }
          return true if membership_ids.uniq.any? do |id|
            membership_class.load(id)&.organization_objid.to_s == objid
          end

          return true if Onetime::CustomDomain.owners.hgetall.values.any? { |id| id.to_s == objid }

          domain_ids = []
          Onetime::CustomDomain.instances.each { |id| domain_ids << id.to_s }
          Onetime::CustomDomain.dbclient.scan_each(match: "#{Onetime::CustomDomain.prefix}:*:object").each do |key|
            domain_ids << key.delete_prefix("#{Onetime::CustomDomain.prefix}:").delete_suffix(':object')
          end
          domain_ids.uniq.any? { |id| Onetime::CustomDomain.load(id)&.org_id.to_s == objid }
        end

        def discover_memberships
          @deep ? discover_memberships_from_sweep : discover_memberships_for_candidates
        rescue StandardError => ex
          add_blocker(:membership_scan_failed, message: ex.class.name)
        end

        # Membership objids are composite(org, customer), so every membership of a
        # KNOWN organization is an O(1) load off that organization's own member and
        # invitation sets. The target's row is loaded directly, which keeps the
        # drift signals about the purge target itself exact even when the org's
        # collections are inconsistent.
        #
        # A row whose customer is missing from `members` is only reachable
        # through the registry. Without a snapshot that residual is accepted on
        # request paths (the through-model writes the row and the set together);
        # a bulk run supplies one so the union is complete for every candidate.
        # Snapshot rows are re-loaded, so a row removed since the capture is
        # skipped rather than reported as drift.
        def discover_memberships_for_candidates
          @organizations.keys.dup.each do |org_id|
            org = @organizations[org_id]

            member_ids = org.members.to_a.map(&:to_s).uniq
            member_ids << customer_objid unless member_ids.include?(customer_objid)
            member_ids.each do |member_id|
              bucket(Onetime::OrganizationMembership.find_by_org_customer(org_id, member_id), org_id)
            end

            org.pending_invitations.to_a.each do |objid|
              bucket(Onetime::OrganizationMembership.load(objid.to_s), org_id)
            end

            @membership_snapshot&.objids_for(org_id)&.each do |objid|
              bucket(Onetime::OrganizationMembership.load(objid), org_id)
            end
          end
        end

        # The sweep lists every registry row by organization and names the rows
        # whose `customer_objid` was the target. Rows are re-loaded here: one
        # removed since the capture is skipped, one that still names the target
        # adds its organization (or an orphan blocker when the organization is
        # gone), and the rows of each candidate organization are bucketed from
        # live state exactly as the per-row registry walk did.
        def discover_memberships_from_sweep
          sweep = @registry_sweep
          add_blocker(:membership_scan_failed, message: sweep.failures[:memberships]) if sweep.failed?(:memberships)

          sweep.target_membership_objids.each do |objid|
            membership = Onetime::OrganizationMembership.load(objid)
            next unless membership && membership.customer_objid.to_s == customer_objid

            org_id = membership.organization_objid.to_s
            next if org_id.empty?

            org = Onetime::Organization.load(org_id)
            if org
              add_organization(org)
            else
              add_blocker(:orphan_customer_membership, membership_id: membership.objid.to_s)
            end
          end

          @organizations.keys.each do |org_id|
            sweep.membership_objids_for(org_id).each do |objid|
              bucket(Onetime::OrganizationMembership.load(objid), org_id)
            end
          end
        end

        def bucket(membership, org_id)
          return unless membership

          target = if membership.active?
                     @active_memberships_by_org[org_id]
                   elsif membership.pending?
                     @pending_memberships_by_org[org_id]
                   else
                     @retained_memberships_by_org[org_id]
                   end
          target << membership unless target.any? { |known| known.objid.to_s == membership.objid.to_s }
        end

        # The sweep names the organizations whose `owner_id`, `members` set or
        # target membership row referenced the customer when it was captured.
        # Each is re-loaded and the reference re-checked against live state, so
        # an organization the purge has since cleaned up drops out here rather
        # than being judged on stale evidence.
        def discover_instances
          return unless @deep

          sweep         = @registry_sweep
          @instance_ids = sweep.organization_ids
          add_blocker(:organization_scan_failed, message: sweep.failures[:organizations]) if sweep.failed?(:organizations)

          sweep.referenced_org_ids.each do |objid|
            org = Onetime::Organization.load(objid)
            next unless org

            add_organization(org) if references_customer?(org)
          end
        rescue StandardError => ex
          add_blocker(:organization_scan_failed, message: ex.class.name)
        end

        def references_customer?(org)
          return true if org.owner_id.to_s == customer_objid
          return true if org.members.to_a.map(&:to_s).include?(customer_objid)

          Onetime::OrganizationMembership.find_by_org_customer(org.objid.to_s, customer_objid)&.active? || false
        end

        # Deep discovery already materialized the whole registry; shallow probes
        # the one id it cares about (a ZSCORE) rather than reading all of them.
        def organization_registered?(org_id)
          return @instance_ids.include?(org_id) if @deep

          @registered_org_ids.fetch(org_id) do
            @registered_org_ids[org_id] = Onetime::Organization.instances.member?(
              Onetime::Organization.new(objid: org_id),
            )
          end
        rescue StandardError
          # An unreadable registry must not read as "present".
          false
        end

        # `contact_email_index` is keyed verbatim, so the holder is resolved
        # through the tolerant finder rather than a normalized HGET — otherwise a
        # Stripe-synced `Jane.Doe@Example.com` reads as unclaimed here and as
        # drifted in {#contact_index_blockers}, refusing the purge forever. The
        # probe is exhaustive: an exact hit must not hide a second spelling held
        # by a different organization, which is the ambiguity refused below.
        def discover_contact_email_holder
          email = normalized_customer_email
          return if email.empty?

          holder_ids = Onetime::Organization.find_contact_email_claims(email, exhaustive: true)
            .values.map(&:to_s).reject(&:empty?).uniq
          if holder_ids.size > 1
            add_blocker(:contact_email_index_ambiguous, holder_count: holder_ids.size)
            return
          end

          @email_holder_id = holder_ids.first.to_s
          return if @email_holder_id.empty?

          org = Onetime::Organization.load(@email_holder_id)
          if org
            add_organization(org)
          else
            add_blocker(:phantom_contact_email_index, holder_id: @email_holder_id)
          end
        rescue StandardError => ex
          add_blocker(:contact_email_lookup_failed, message: ex.class.name)
        end

        def check_domain_scan
          return unless @registry_sweep.failed?(:domains)

          add_blocker(:domain_scan_failed, message: @registry_sweep.failures[:domains])
        end

        def add_organization(org)
          @organizations[org.objid.to_s] = org
        end

        # rubocop:disable Metrics/PerceivedComplexity -- decision table: every branch is
        # one named blocker or one piece of action evidence
        def classify(org)
          org_id                  = org.objid.to_s
          org_ref                 = public_org_id(org)
          raw_member_ids          = org.members.to_a.map(&:to_s).uniq
          active_memberships      = @active_memberships_by_org.fetch(org_id, [])
          active_customer_ids     = active_memberships.map { |membership| membership.customer_objid.to_s }.uniq
          all_customer_ids        = (raw_member_ids + active_customer_ids).uniq
          live_members            = all_customer_ids.to_h { |objid| [objid, Onetime::Customer.load(objid)] }
          stale_member_ids        = live_members.select { |_objid, customer| customer.nil? }.keys
          raw_memberships         = raw_member_ids.to_h do |objid|
            [objid, Onetime::OrganizationMembership.find_by_org_customer(org_id, objid)]
          end
          owner_memberships       = active_memberships.select(&:owner?)
          target_membership       = Onetime::OrganizationMembership.find_by_org_customer(org_id, customer_objid)
          target_in_members       = raw_member_ids.include?(customer_objid)
          target_participates     = @participation_ids.include?(org_id)
          target_active           = target_membership&.active? || false
          target_owns             = target_active && target_membership.owner?
          target_pending          = @pending_memberships_by_org.fetch(org_id, []).any? do |membership|
            membership.customer_objid.to_s == customer_objid
          end
          target_retained         = @retained_memberships_by_org.fetch(org_id, []).any? do |membership|
            membership.customer_objid.to_s == customer_objid
          end

          org_blockers = []
          org_blockers << :organization_instance_missing unless organization_registered?(org_id)
          org_blockers << :stale_members if stale_member_ids.any?
          org_blockers << :membership_record_missing if raw_memberships.any? { |_id, membership| !membership&.active? }
          org_blockers << :membership_index_drift unless raw_member_ids.sort == active_customer_ids.sort
          org_blockers << :target_membership_drift if target_in_members != target_active
          org_blockers << :target_participation_drift if target_in_members != target_participates
          org_blockers << :pending_customer_membership if target_pending
          org_blockers << :inactive_customer_membership if target_retained
          org_blockers.concat(ownership_blockers(org, owner_memberships, live_members))
          org_blockers.concat(contact_index_blockers(org))

          if contact_email_holder?(org) && !target_in_members && org.owner_id.to_s != customer_objid
            org_blockers << :contact_email_collision
          end

          if target_owns || org.owner_id.to_s == customer_objid
            org_blockers.concat(
              owned_workspace_blockers(
                org,
                raw_member_ids,
                stale_member_ids,
                owner_memberships,
                target_membership,
              ),
            )
            record_org_blockers(org_ref, org_blockers)
            return nil if org_blockers.any?

            return Action.new(
              type: :delete_organization,
              organization: org,
              org_id: org_ref,
              role: 'owner',
              notes: owned_workspace_notes(org),
            )
          end

          if target_active
            org_blockers << :owner_membership_ambiguous if target_membership.owner?
            record_org_blockers(org_ref, org_blockers)
            return nil if org_blockers.any?

            return Action.new(
              type: :remove_membership,
              organization: org,
              org_id: org_ref,
              role: target_membership.role.to_s,
            )
          end

          # Discovery found a reference but no complete active relationship.
          if target_in_members || target_participates || org.owner_id.to_s == customer_objid || contact_email_holder?(org)
            org_blockers << :unresolved_customer_reference
          end
          record_org_blockers(org_ref, org_blockers)
          nil
        rescue StandardError => ex
          add_blocker(
            :organization_evidence_incomplete,
            org_id: public_org_id(org),
            message: ex.class.name,
          )
          nil
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def ownership_blockers(org, owner_memberships, live_members)
          # A legacy `owner_id` holding the target's custid names the same person
          # as their objid; resolve it before comparing against member objids.
          owner_id = customer_reference?(org.owner_id) ? customer_objid : org.owner_id.to_s
          blockers = []
          blockers << :owner_id_missing if owner_id.empty?
          blockers << :owner_missing unless owner_id.empty? || live_members[owner_id]
          blockers << :owner_not_member unless owner_id.empty? || live_members.key?(owner_id)
          blockers << :owner_membership_count unless owner_memberships.one?
          if owner_memberships.one? && owner_memberships.first.customer_objid.to_s != owner_id
            blockers << :owner_membership_mismatch
          end
          blockers
        end

        # The index stores the address exactly as the org carries it, so the
        # org's own `contact_email` is the authoritative probe key. The tolerant
        # finder covers the remaining case where the stored key and the field
        # disagree only in case or Unicode form.
        #
        # No contact email is not drift: the workspace modal submits none,
        # `Organization.create!` persists nil and reserves nothing, and
        # `delete!` skips the index for it. Only a carried address can disagree
        # with the index.
        def contact_index_blockers(org)
          return [] if normalized_email(org.contact_email).empty?

          holder = Onetime::Organization.contact_email_index.get(org.contact_email.to_s).to_s
          holder = Onetime::Organization.find_contact_email_holder_id(org.contact_email).to_s if holder.empty?
          holder == org.objid.to_s ? [] : [:contact_email_index_drift]
        end

        def owned_workspace_blockers(org, raw_member_ids, stale_member_ids,
                                     owner_memberships, target_membership)
          blockers       = []
          blockers << :not_default_workspace unless org.is_default.to_s == 'true'
          blockers << :default_workspace_mismatch if competing_default_workspace?(org)
          blockers << :target_not_owner unless target_membership&.active? && target_membership.owner?
          blockers << :not_sole_owner unless owner_memberships.one? &&
                                             owner_memberships.first.customer_objid.to_s == customer_objid
          # Ownership remains tied to current identity and active memberships.
          # Creator attribution can carry a preserved v1 identity instead.
          blockers << :owner_id_mismatch unless customer_reference?(org.owner_id)
          blockers << :creator_mismatch unless creator_reference?(org)
          blockers << :other_members unless raw_member_ids == [customer_objid]
          blockers << :stale_members if stale_member_ids.any?
          blockers << :has_domains if org.domain_count.to_i.positive?
          blockers << :drifted_domains if drifted_domains?(org)
          blockers.concat(invitation_blockers(org))
          blockers << :retained_membership_records if @retained_memberships_by_org.fetch(org.objid.to_s, []).any?
          blockers << :billing_state if billing_state?(org)
          blockers << :migration_in_flight if migration_in_flight?(org)
          blockers.uniq
        end

        # default_org_id is the customer's preference, deleted with the
        # customer record. SSO sign-in on a custom domain points it at the
        # tenant organization the customer joined, and a removal could leave
        # it naming an organization they no longer belong to; neither is a
        # reason to refuse. It is refused only when it names a second default
        # workspace the customer owns, which leaves two candidates for the one
        # workspace a purge deletes. A pointer to an organization that is
        # gone is ignored, as in {#discover_participations}.
        def competing_default_workspace?(org)
          default_org_id = @customer.default_org_id.to_s
          return false if default_org_id.empty? || default_org_id == org.objid.to_s

          other = @organizations[default_org_id] || Onetime::Organization.load(default_org_id)
          return false unless other && other.is_default.to_s == 'true'
          return true if customer_reference?(other.owner_id)

          membership = Onetime::OrganizationMembership.find_by_org_customer(default_org_id, customer_objid)
          (membership&.active? && membership.owner?) || false
        end

        # Content of the sole-owner default workspace that goes WITH the
        # organization: the workspace description, a contact address that
        # diverged from the account's (the billing-email sync writes it), and
        # outstanding invitations the departing owner sent. Receipts are listed
        # for the same reason but are not destroyed by any purge path: the
        # organization's receipt index is dropped with it, while the Receipt
        # and Secret records are TTL-bound and expire on their own schedule.
        # None of it belongs to another party, so none of it is a reason to
        # refuse an erasure request. Reported so an operator can still see what
        # a purge removed. Drift-shaped signals stay in {#owned_workspace_blockers}.
        def owned_workspace_notes(org)
          notes = []
          notes << :has_receipts if org.receipt_count.to_i.positive?
          notes << :pending_invitations if org.pending_invitation_count.to_i.positive?
          notes << :contact_email_mismatch unless normalized_email(org.contact_email) == normalized_customer_email
          notes.concat(retained_data_fields(org).map { |field| :"retained_#{field}" })
          notes.uniq
        end

        def customer_reference?(value)
          reference = value.to_s
          return false if reference.empty?

          reference == customer_objid || reference == @customer.custid.to_s
        end

        def legacy_customer_reference?(value)
          field_present?(@customer, :v1_custid) && value.to_s == @customer.v1_custid.to_s
        end

        def creator_reference?(org)
          creator = org.created_by.to_s
          return true if customer_reference?(creator)
          return true if legacy_customer_reference?(creator)

          # The v1 organization generator omitted created_by. Its completed
          # output names the transformed customer key and original custid; both
          # must bind to this customer. Email/contact equality alone is not proof
          # of identity, and this fallback must never overwrite a different creator.
          return false unless creator.empty? && org.migration_status.to_s == 'completed'
          return false unless org.v1_identifier.to_s == @customer.dbkey.to_s

          customer_reference?(org.v1_source_custid) || legacy_customer_reference?(org.v1_source_custid)
        end

        def migration_in_flight?(record)
          return false unless record.respond_to?(:migration_status)

          # Successful create_from_v1_customer! also writes provenance without a
          # status. Only explicit state is a migration gate; timestamps, comments,
          # and source identifiers remain useful after migration has finished.
          status = record.migration_status.to_s.strip
          !status.empty? && status != 'completed'
        end

        def invitation_blockers(org)
          raw_ids     = org.pending_invitations.to_a.map(&:to_s).sort
          indexed_ids = @pending_memberships_by_org.fetch(org.objid.to_s, []).map { |membership| membership.objid.to_s }.sort
          blockers    = []
          blockers << :pending_invitation_drift unless raw_ids == indexed_ids
          blockers
        end

        # Both directions are covered without the global CustomDomain registry:
        # `unlisted_owned_domains` reads the owners hashkey for records pointing
        # AT this organization but missing from its list, and the listed ids are
        # existence-checked for the reverse. Deep discovery keeps the registry
        # evidence: the sweep names every domain whose `org_id` pointed at this
        # organization, and each is re-loaded so the comparison is live.
        def drifted_domains?(org)
          return true if org.unlisted_owned_domains.any?

          org_id         = org.objid.to_s
          listed_ids     = org.domains.to_a.map(&:to_s).sort
          referenced_ids = if @deep
                             @registry_sweep.domain_objids_for(org_id).select do |objid|
                               Onetime::CustomDomain.load(objid)&.org_id.to_s == org_id
                             end.sort
                           else
                             listed_ids.select { |objid| Onetime::CustomDomain.load(objid) }.sort
                           end
          referenced_ids != listed_ids
        end

        def billing_state?(org)
          return true if org.billing_live?

          status = org.subscription_status.to_s.strip
          return true unless status.empty? || NON_LIVE_SUBSCRIPTION_STATUSES.include?(status)
          return true if status.empty? && field_present?(org, :stripe_subscription_id)

          BILLING_MIGRATION_FIELDS.any? { |field| billing_status_present?(org, field) }
        end

        def retained_data_fields(org)
          fields = RETAINED_SCALAR_FIELDS.select { |field| field_present?(org, field) }
          fields << :urls if data_type_present?(org, :urls, :hgetall)
          fields << :caboose if meaningful_json?(org.respond_to?(:caboose) ? org.caboose : nil)
          fields << :secret_activity_events if org.respond_to?(:secret_activity_event_count) &&
                                               org.secret_activity_event_count.to_i.positive?
          fields << :entitlements_grants if data_type_present?(org, :entitlements_grants, :to_a)
          fields << :entitlements_revokes if data_type_present?(org, :entitlements_revokes, :to_a)
          fields
        end

        def data_type_present?(org, field, reader)
          return false unless org.respond_to?(field)

          value = org.public_send(field)
          value.respond_to?(reader) && value.public_send(reader).to_a.any?
        end

        def meaningful_json?(value)
          string = (value.to_s || '').strip
          !string.empty? && !%w[{} [] null].include?(string)
        end

        def field_present?(org, field)
          org.respond_to?(field) && !org.public_send(field).to_s.strip.empty?
        end

        def billing_status_present?(org, field)
          return false unless org.respond_to?(field)

          value = org.public_send(field).to_s.strip
          return false if value.empty?
          return false if field == :pending_currency_migration && value == 'false'

          true
        end

        def contact_email_holder?(org)
          !@email_holder_id.to_s.empty? && @email_holder_id.to_s == org.objid.to_s
        end

        def attach_account_purge_contexts(plan)
          signature = plan.signature
          actions   = plan.actions.map do |action|
            next action unless action.type == :delete_organization

            Action.new(
              type: action.type,
              organization: action.organization,
              org_id: action.org_id,
              role: action.role,
              notes: action.notes,
              account_purge_context: AccountPurgeContext.new(
                customer: @customer,
                organization_objid: action.organization.objid,
                plan_signature: signature,
                deep: @deep,
                membership_snapshot: @membership_snapshot,
                registry_sweep: @registry_sweep,
              ),
            )
          end
          Plan.new(actions: actions, blockers: plan.blockers)
        end

        def valid_purge_organization_id?(objid)
          objid && objid.match?(/\A[A-Za-z0-9_-]+\z/)
        end

        def organization_id_from_participation(key)
          match = key.match(/\A(?:organization|org):([^:]+):members\z/)
          match && match[1]
        end

        def record_org_blockers(org_id, blockers)
          blockers.uniq.each { |code| add_blocker(code, org_id: org_id) }
        end

        def add_blocker(code, **detail)
          blocker = { code: code }.merge(detail)
          @blockers << blocker unless @blockers.include?(blocker)
        end

        def sorted_blockers
          @blockers.sort_by { |blocker| blocker.sort_by { |key, _value| key.to_s }.to_s }
        end

        def normalized_customer_email
          @normalized_customer_email ||= normalized_email(@customer.email)
        end

        def normalized_email(value)
          OT::Utils.normalize_email(value.to_s).to_s
        end

        def customer_objid
          @customer.objid.to_s
        end

        def public_org_id(org)
          org&.extid.to_s.empty? ? 'unknown' : org.extid.to_s
        rescue StandardError
          'unknown'
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
