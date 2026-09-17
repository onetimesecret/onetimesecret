# apps/web/auth/operations/customers/purge_preflight.rb
#
# frozen_string_literal: true

module Auth
  module Operations
    module Customers
      # Read-only, drift-tolerant organization preflight for an administrative
      # customer purge. A plan is executable only when every discovered
      # relationship is complete and unambiguous.
      # rubocop:disable Metrics/ClassLength -- one blocker taxonomy; splitting it
      # would scatter the refusal rules across files
      class PurgePreflight
        BILLING_IDENTIFIER_FIELDS = [
          :stripe_customer_id,
          :stripe_subscription_id,
          :stripe_checkout_email,
          :billing_email,
          :email_hash,
          :email_hash_synced_at,
        ].freeze

        BILLING_STATUS_FIELDS = [
          :subscription_status,
          :subscription_period_end,
          :subscription_federated_at,
          :federation_notification_dismissed_at,
          :complimentary,
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

        # A half-finished v1->v2 migration is NOT the account's own content: the
        # migration owns rows outside this organization, so deleting it here
        # would strand them. These stay blocking.
        IN_FLIGHT_MIGRATION_FIELDS = [
          :v1_identifier,
          :v1_source_custid,
          :migration_status,
          :migrated_at,
          :migration_comment,
        ].freeze

        class Action
          attr_reader :type, :organization, :org_id, :role, :notes, :account_purge_context

          def initialize(type:, organization:, org_id:, role:, notes: [], account_purge_context: nil)
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
            detail = { type: type, org_id: org_id, role: role, status: status }
            notes.empty? ? detail : detail.merge(notes: notes)
          end
        end

        Plan = Data.define(:actions, :blockers) do
          def executable? = blockers.empty?

          def signature
            [
              actions.map { |action| [action.type, action.organization.objid.to_s, action.role.to_s] }.sort,
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

          def initialize(customer:, organization_objid:, plan_signature:, deep: false)
            @customer             = customer
            @customer_objid       = customer.objid.to_s
            @organization_objid   = organization_objid.to_s
            @plan_signature       = plan_signature
            @deep                 = deep
          end

          def authorized_for?(organization)
            return false unless organization.objid.to_s == @organization_objid

            plan = PurgePreflight.new(customer: @customer, deep: @deep).call
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
        #   their participations), at a cost of three full registry scans PER
        #   CALL. `Purge` re-runs preflight once per action plus three teardown
        #   revalidations, so deep discovery is reserved for operator sweeps that
        #   can afford it and is never used on a request path. Shallow discovery
        #   reaches the same organizations through the customer's own reverse
        #   indexes (participations, organization_instances, default_org_id and
        #   the contact-email claim) and keeps every per-organization drift check.
        def initialize(customer:, deep: false)
          @customer                    = customer
          @deep                        = deep
          @registered_org_ids          = {}
          @blockers                    = []
          @organizations               = {}
          @participation_ids           = []
          @instance_ids                = []
          @email_holder_id             = nil
          @active_memberships_by_org   = Hash.new { |hash, key| hash[key] = [] }
          @pending_memberships_by_org  = Hash.new { |hash, key| hash[key] = [] }
          @retained_memberships_by_org = Hash.new { |hash, key| hash[key] = [] }
          @domain_references_by_org    = Hash.new { |hash, key| hash[key] = [] }
        end

        # @return [Plan]
        def call
          discover_participations
          discover_contact_email_holder
          discover_instances
          discover_memberships
          discover_domain_references if @deep

          actions = @organizations.values.filter_map { |org| classify(org) }
            .sort_by { |action| [action.organization.objid.to_s, action.type.to_s] }
          plan    = Plan.new(actions: actions, blockers: sorted_blockers)

          attach_account_purge_contexts(plan)
        rescue StandardError => ex
          add_blocker(:preflight_incomplete, message: ex.class.name)
          Plan.new(actions: [], blockers: sorted_blockers)
        end

        private

        def discover_participations
          raw_keys           = @customer.participations.to_a.map(&:to_s)
          @participation_ids = raw_keys.filter_map { |key| organization_id_from_participation(key) }.uniq

          @participation_ids.each do |objid|
            org = Onetime::Organization.load(objid)
            if org
              add_organization(org)
            else
              add_blocker(:dangling_customer_participation, reference: "organization:#{objid}:members")
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

        def discover_memberships
          @deep ? discover_memberships_globally : discover_memberships_for_candidates
        rescue StandardError => ex
          add_blocker(:membership_scan_failed, message: ex.class.name)
        end

        # Membership objids are composite(org, customer), so every membership of a
        # KNOWN organization is an O(1) load off that organization's own member and
        # invitation sets. The target's row is loaded directly, which keeps the
        # drift signals about the purge target itself exact even when the org's
        # collections are inconsistent.
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
          end
        end

        def discover_memberships_globally
          Onetime::OrganizationMembership.instances.each do |objid|
            membership = Onetime::OrganizationMembership.load(objid)
            next unless membership

            org_id = membership.organization_objid.to_s
            next if org_id.empty?

            bucket(membership, org_id)

            next unless membership.customer_objid.to_s == customer_objid

            org = Onetime::Organization.load(org_id)
            if org
              add_organization(org)
            else
              add_blocker(:orphan_customer_membership, membership_id: membership.objid.to_s)
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

        def discover_instances
          return unless @deep

          Onetime::Organization.instances.each do |objid|
            objid = objid.to_s
            @instance_ids << objid
            org   = Onetime::Organization.load(objid)
            next unless org

            raw_member_ids  = org.members.to_a.map(&:to_s)
            target_relation = Onetime::OrganizationMembership.find_by_org_customer(objid, customer_objid)
            referenced      = org.owner_id.to_s == customer_objid ||
                              raw_member_ids.include?(customer_objid) ||
                              target_relation&.active?
            add_organization(org) if referenced
          end
        rescue StandardError => ex
          add_blocker(:organization_scan_failed, message: ex.class.name)
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
        # drifted in {#contact_index_blockers}, refusing the purge forever.
        def discover_contact_email_holder
          email = normalized_customer_email
          return if email.empty?

          holder_ids = Onetime::Organization.find_contact_email_claims(email)
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

        def discover_domain_references
          Onetime::CustomDomain.instances.each do |objid|
            domain = Onetime::CustomDomain.load(objid)
            next unless domain

            org_id = domain.org_id.to_s
            @domain_references_by_org[org_id] << domain unless org_id.empty?
          end
        rescue StandardError => ex
          add_blocker(:domain_scan_failed, message: ex.class.name)
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
        def contact_index_blockers(org)
          return [:contact_email_missing] if normalized_email(org.contact_email).empty?

          holder = Onetime::Organization.contact_email_index.get(org.contact_email.to_s).to_s
          holder = Onetime::Organization.find_contact_email_holder_id(org.contact_email).to_s if holder.empty?
          holder == org.objid.to_s ? [] : [:contact_email_index_drift]
        end

        def owned_workspace_blockers(org, raw_member_ids, stale_member_ids,
                                     owner_memberships, target_membership)
          blockers       = []
          blockers << :not_default_workspace unless org.is_default.to_s == 'true'
          default_org_id = @customer.default_org_id.to_s
          blockers << :default_workspace_mismatch unless default_org_id.empty? || default_org_id == org.objid.to_s
          blockers << :target_not_owner unless target_membership&.active? && target_membership.owner?
          blockers << :not_sole_owner unless owner_memberships.one? &&
                                             owner_memberships.first.customer_objid.to_s == customer_objid
          # `owner_id`/`created_by` are compared tolerantly: rows predating the
          # objid standardization chore still carry the customer's custid, and a
          # legacy encoding is not drift.
          blockers << :owner_id_mismatch unless customer_reference?(org.owner_id)
          blockers << :creator_mismatch unless customer_reference?(org.created_by)
          blockers << :other_members unless raw_member_ids == [customer_objid]
          blockers << :stale_members if stale_member_ids.any?
          blockers << :has_domains if org.domain_count.to_i.positive?
          blockers << :drifted_domains if drifted_domains?(org)
          blockers.concat(invitation_blockers(org))
          blockers << :retained_membership_records if @retained_memberships_by_org.fetch(org.objid.to_s, []).any?
          blockers << :billing_state if billing_state?(org)
          blockers << :migration_in_flight if IN_FLIGHT_MIGRATION_FIELDS.any? { |field| field_present?(org, field) }
          blockers.uniq
        end

        # Content of the sole-owner default workspace that is deleted WITH the
        # organization: receipts, the workspace description, a contact address
        # that diverged from the account's (the billing-email sync writes it),
        # and outstanding invitations the departing owner sent. None of it
        # belongs to another party, so none of it is a reason to refuse an
        # erasure request. Reported so an operator can still see what a purge
        # removed. Drift-shaped signals stay in {#owned_workspace_blockers}.
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
        # existence-checked for the reverse. Deep discovery keeps using the
        # materialized reference map so its evidence is unchanged.
        def drifted_domains?(org)
          return true if org.unlisted_owned_domains.any?

          listed_ids     = org.domains.to_a.map(&:to_s).sort
          referenced_ids = if @deep
                             @domain_references_by_org.fetch(org.objid.to_s, [])
                               .map { |domain| domain.objid.to_s }.sort
                           else
                             listed_ids.select { |objid| Onetime::CustomDomain.load(objid) }.sort
                           end
          referenced_ids != listed_ids
        end

        def billing_state?(org)
          return true if org.billing_live?
          return true if BILLING_IDENTIFIER_FIELDS.any? { |field| field_present?(org, field) }
          return true if BILLING_STATUS_FIELDS.any? { |field| billing_status_present?(org, field) }

          planid = org.planid.to_s
          !planid.empty? && planid != 'free_v1'
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
          return false if [:complimentary, :pending_currency_migration].include?(field) && value == 'false'

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
              ),
            )
          end
          Plan.new(actions: actions, blockers: plan.blockers)
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
