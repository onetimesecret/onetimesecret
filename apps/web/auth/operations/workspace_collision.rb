# apps/web/auth/operations/workspace_collision.rb
#
# frozen_string_literal: true

require 'json'

module Auth
  module Operations
    # Read-only classification of the Organization contact-email claim that can
    # block default-workspace provisioning. The raw index is the discovery
    # source; customer participation is evidence only and is never used to find
    # the holder.
    class WorkspaceCollision
      CLASSIFICATIONS = [
        :clear,
        :phantom_index,
        :index_mismatch,
        :current_valid_workspace,
        :empty_orphan,
        :stale_members,
        :live_members,
        :retained_data,
        :unreadable,
      ].freeze

      BILLING_FIELDS = [
        :stripe_customer_id,
        :stripe_subscription_id,
        :stripe_checkout_email,
        :billing_email,
        :email_hash,
        :email_hash_synced_at,
        :subscription_status,
        :subscription_period_end,
        :subscription_federated_at,
        :federation_notification_dismissed_at,
        :complimentary,
        :pending_currency_migration,
        :migration_target_price_id,
        :migration_effective_after,
      ].freeze

      RETAINED_SCALAR_FIELDS = [
        :description,
        :archived_at,
        :archived_comment,
        :v1_identifier,
        :v1_source_custid,
        :migration_status,
        :migrated_at,
        :migration_comment,
      ].freeze

      REPORTABLE_EMAIL_FIELDS = [:normalized_email, :index_key, :contact_email].freeze

      COMPARE_AND_DELETE_SCRIPT = <<~LUA
        if redis.call('HGET', KEYS[1], ARGV[1]) ~= ARGV[2] then return 0 end
        return redis.call('HDEL', KEYS[1], ARGV[1])
      LUA

      Result = Data.define(:classification, :email, :index_key, :organization, :raw_index_value, :evidence) do
        # `index_key` is the VERBATIM index field the claim was found under,
        # which is what a repair must HDEL; it defaults to the normalized address
        # for the callers that only ever see the two spellings agree.
        def initialize(index_key: nil, **rest)
          super(index_key: index_key || rest[:email], **rest)
        end

        def clear? = classification == :clear
        def current_valid_workspace? = classification == :current_valid_workspace
        def unreadable? = classification == :unreadable

        def repairable_index_claim?
          [:phantom_index, :index_mismatch].include?(classification) &&
            Array(evidence[:contact_email_claimant_ids]).empty?
        end

        def to_h
          {
            available: !unreadable?,
            classification: classification,
            email: OT::Utils.obscure_email(email.to_s),
            repairable: repairable_index_claim?,
            reason: (evidence[:reason] if unreadable?),
            reason_code: (:workspace_collision_unreadable if unreadable?),
            evidence: WorkspaceCollision.reportable_evidence(evidence),
          }.compact
        end
      end

      def self.reportable_evidence(evidence)
        reportable = evidence.dup
        REPORTABLE_EMAIL_FIELDS.each do |field|
          next unless reportable.key?(field)

          reportable[field] = OT::Utils.obscure_email(reportable[field].to_s)
        end
        reportable
      end

      class ProvisioningCollision < Onetime::Problem
        attr_reader :collision

        def initialize(collision)
          @collision = collision
          super("Default workspace provisioning collision: #{collision.classification}")
        end
      end

      def initialize(email:, customer: nil)
        @email    = normalize_email(email)
        @customer = customer
      end

      # @return [Result]
      def call
        return result(:clear, evidence: base_evidence(index_present: false)) if @email.empty?

        # The index is keyed VERBATIM (see Organization.find_contact_email_claims):
        # a normalized HGET misses a claim stored as `Jane.Doe@Example.com` and
        # would report a real collision as `:clear`, letting provisioning proceed
        # into a duplicate workspace.
        index = Onetime::Organization.contact_email_index
        claim = Onetime::Organization.find_contact_email_claims(@email).first
        return result(:clear, evidence: base_evidence(index_present: false)) if claim.nil?

        @index_key = claim.first
        raw        = index.dbclient.hget(index.dbkey, @index_key)
        return result(:clear, evidence: base_evidence(index_present: false)) if raw.nil?

        holder_id = decode_index_value(raw)
        evidence  = base_evidence(index_present: true, index_holder_objid: holder_id)
        if holder_id.empty?
          evidence = with_contact_claimants(evidence).merge(organization_found: false)
          return result(:phantom_index, raw: raw, evidence: evidence)
        end

        organization = Onetime::Organization.load(holder_id)
        unless organization
          evidence = with_contact_claimants(evidence).merge(organization_found: false)
          return result(:phantom_index, raw: raw, evidence: evidence)
        end

        evidence       = organization_evidence(organization, evidence)
        evidence       = with_contact_claimants(evidence) unless evidence[:contact_email_matches]
        classification = classify(organization, evidence)
        result(classification, organization: organization, raw: raw, evidence: evidence)
      rescue StandardError => ex
        result(
          :unreadable,
          evidence: base_evidence.merge(
            error: ex.class.name,
            reason: ex.message,
          ),
        )
      end

      # Remove only the exact raw claim observed by this result. A claimant that
      # changes the field after classification wins and is left untouched.
      def self.compare_and_delete(result)
        return false unless result.repairable_index_claim?
        return false if result.raw_index_value.nil?

        index = Onetime::Organization.contact_email_index
        index.dbclient.eval(
          COMPARE_AND_DELETE_SCRIPT,
          keys: [index.dbkey],
          # The STORED key, not the normalized address: the index is keyed
          # verbatim, so deleting by `result.email` would be a no-op on any
          # claim that was written with different case.
          argv: [result.index_key.to_s, result.raw_index_value],
        ).to_i == 1
      end

      private

      def result(classification, evidence:, organization: nil, raw: nil)
        Result.new(
          classification: classification,
          email: @email,
          index_key: @index_key,
          organization: organization,
          raw_index_value: raw,
          evidence: evidence,
        )
      end

      def base_evidence(**extra)
        {
          normalized_email: @email,
          index_key: @index_key,
          index_read_independently: true,
        }.compact.merge(extra)
      end

      def organization_evidence(org, evidence)
        org_id                 = org.objid.to_s
        raw_member_ids         = org.members.to_a.map(&:to_s).uniq
        loaded_members         = raw_member_ids.to_h { |objid| [objid, Onetime::Customer.load(objid)] }
        live_member_ids        = loaded_members.filter_map { |objid, customer| objid if customer }
        stale_member_ids       = loaded_members.filter_map { |objid, customer| objid unless customer }
        current_membership     = current_membership_for(org_id)
        listed_domain_ids      = org.domains.to_a.map(&:to_s).uniq.sort
        live_listed_domain_ids = listed_domain_ids.select { |objid| Onetime::CustomDomain.load(objid) }
        # Bounded second source, same pair purge_preflight uses: the owners
        # hashkey (one HGETALL, loads only drifted ids) instead of a walk of the
        # whole CustomDomain registry, which this runs on colonel and signup
        # request paths.
        unlisted_domain_ids    = org.unlisted_owned_domains.map { |domain| domain.objid.to_s }.uniq.sort
        referenced_domain_ids  = (live_listed_domain_ids + unlisted_domain_ids).uniq.sort
        raw_invitation_ids     = org.pending_invitations.to_a.map(&:to_s).uniq
        billing_markers        = present_fields(org, BILLING_FIELDS, boolean_false_is_empty: true)
        retained_markers       = retained_data_markers(org)
        owner_id               = org.owner_id.to_s
        owner                  = owner_id.empty? ? nil : Onetime::Customer.load(owner_id)

        evidence.merge(
          organization_found: true,
          organization_objid: org_id,
          organization_extid: org.extid,
          is_default: org.is_default.to_s == 'true',
          contact_email: org.contact_email,
          contact_email_matches: normalize_email(org.contact_email) == @email,
          owner_id: owner_id,
          owner_alive: !owner.nil?,
          owner_extid: owner&.extid,
          current_customer_in_members: current_customer_id ? raw_member_ids.include?(current_customer_id) : false,
          current_customer_membership_active: current_membership&.active? || false,
          current_customer_owner: (current_membership&.active? && current_membership.owner?) || false,
          member_count: raw_member_ids.size,
          live_member_ids: live_member_ids,
          live_member_extids: loaded_members.values.compact.map(&:extid),
          stale_member_ids: stale_member_ids,
          domain_ids: listed_domain_ids,
          domain_count: listed_domain_ids.size,
          domain_reference_ids: referenced_domain_ids,
          domain_drift: listed_domain_ids != referenced_domain_ids,
          invitation_ids: raw_invitation_ids,
          invitation_count: raw_invitation_ids.size,
          receipt_count: org.receipts.size,
          billing_markers: billing_markers,
          retained_data_markers: retained_markers,
        )
      end

      def classify(org, evidence)
        return :index_mismatch unless evidence[:contact_email_matches]
        return :current_valid_workspace if valid_current_workspace?(org, evidence)
        return :retained_data if retained_data?(evidence)
        return :stale_members if evidence[:stale_member_ids].any?
        return :live_members if evidence[:live_member_ids].any? || evidence[:owner_alive]

        :empty_orphan
      end

      def valid_current_workspace?(org, evidence)
        return false unless current_customer_id

        evidence[:is_default] &&
          evidence[:owner_id] == current_customer_id &&
          evidence[:owner_alive] &&
          evidence[:current_customer_in_members] &&
          evidence[:current_customer_membership_active] &&
          evidence[:current_customer_owner] &&
          evidence[:stale_member_ids].empty? &&
          !evidence[:domain_drift] &&
          org.objid.to_s == evidence[:organization_objid]
      end

      def retained_data?(evidence)
        evidence[:domain_count].positive? ||
          evidence[:domain_drift] ||
          evidence[:invitation_count].positive? ||
          evidence[:receipt_count].positive? ||
          evidence[:billing_markers].any? ||
          evidence[:retained_data_markers].any?
      end

      def current_membership_for(org_id)
        return nil unless current_customer_id

        Onetime::OrganizationMembership.find_by_org_customer(org_id, current_customer_id)
      end

      def with_contact_claimants(evidence)
        claimants = contact_email_claimants
        evidence.merge(
          contact_email_claimant_ids: claimants.map { |org| org.objid.to_s },
          contact_email_claimant_extids: claimants.map(&:extid),
        )
      end

      # Independent of the index holder: a stale pointer is not safely removable
      # if another live organization already carries the address but is itself
      # missing from the index. Deleting in that state would let provisioning
      # reserve the field and create a duplicate workspace.
      def contact_email_claimants
        Onetime::Organization.instances.to_a.filter_map do |objid|
          org = Onetime::Organization.load(objid)
          org if org && normalize_email(org.contact_email) == @email
        end
      end

      def retained_data_markers(org)
        fields = present_fields(org, RETAINED_SCALAR_FIELDS)
        fields << :urls if collection_present?(org, :urls, :hgetall)
        fields << :caboose if meaningful_json?(org.respond_to?(:caboose) ? org.caboose : nil)
        fields << :secret_activity_events if org.respond_to?(:secret_activity_event_count) &&
                                             org.secret_activity_event_count.to_i.positive?
        fields << :entitlements_grants if collection_present?(org, :entitlements_grants, :to_a)
        fields << :entitlements_revokes if collection_present?(org, :entitlements_revokes, :to_a)
        fields
      end

      def present_fields(org, fields, boolean_false_is_empty: false)
        fields.select do |field|
          next false unless org.respond_to?(field)

          raw_value = org.public_send(field)
          value     = raw_value.nil? ? '' : raw_value.to_s
          value     = value.to_s.strip
          next false if value.empty?
          next false if boolean_false_is_empty && [:complimentary, :pending_currency_migration].include?(field) && value == 'false'

          true
        end
      end

      def collection_present?(org, field, reader)
        return false unless org.respond_to?(field)

        value = org.public_send(field)
        value.respond_to?(reader) && value.public_send(reader).to_a.any?
      end

      def meaningful_json?(value)
        string = value.nil? ? '' : value.to_s
        string = string.to_s.strip
        !string.empty? && !%w[{} [] null].include?(string)
      end

      # `@customer&.objid.to_s` parses as `(@customer&.objid).to_s`, which is the
      # TRUTHY empty string when no customer was supplied — every `unless
      # current_customer_id` guard below would then run anyway and look up a
      # membership keyed on an empty customer id. Memoized with `defined?` so a
      # nil result is not recomputed.
      def current_customer_id
        return @current_customer_id if defined?(@current_customer_id)

        objid                = @customer&.objid.to_s
        @current_customer_id = objid.empty? ? nil : objid
      end

      def normalize_email(email)
        value = email.to_s.strip
        return '' if value.empty?

        OT::Utils.normalize_email(value)
      end

      def decode_index_value(raw)
        value = raw.to_s
        return '' if value.empty?
        return value unless value.start_with?('"')

        JSON.parse(value).to_s
      rescue JSON::ParserError
        value
      end
    end
  end
end
