# apps/api/organizations/logic/organizations/list_secret_activity.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Organizations
    # List Secret Activity
    #
    # @api Returns a page of the organization's secret activity trail,
    #   newest first: secret creation, link/status fetches, reveals, burns
    #   and expiries recorded for receipts created in this organization's
    #   context (see Organization::Features::SecretActivity). Requires the
    #   `audit_logs` entitlement, which the role/plan intersection grants to
    #   admins and owners on plans that include it.
    #
    #   Event kinds: 'created' (secret concealed/generated), 'status_get'
    #   / 'secret_get' (a third party fetched the status/secret link),
    #   'previewed' (the creator opened their own secret link — the
    #   creator-facing "preview" event), 'creator_status_get' (the creator
    #   checked their own secret's status), 'receipt_viewed' (the creator's
    #   receipt/metadata page was loaded — distinct from opening the secret
    #   link itself), 'revealed', 'burned', 'expired', 'orphaned'. Events
    #   carry receipt/secret shortids only — never full identifiers, which
    #   are capability tokens. Custom-domain shares additionally carry
    #   domain context: 'domain_id' (8-char shortid) and 'domain' (the
    #   public FQDN, e.g. secrets.acme.com); both are absent for
    #   default-domain shares.
    #
    #   Actor identity is different: events carry the FULL customer objid
    #   (an objid grants no access, and NIST AU-3 / PCI DSS 10.2.2 require
    #   unique traceability to an individual). The objid is resolved to
    #   email/extid at read time via the org-membership join
    #   (`details.actors`); actors that no longer resolve — removed members,
    #   out-of-org actors, legacy truncated ids — are absent from the map and
    #   render as the bare objid.
    class ListSecretActivity < OrganizationAPI::Logic::Base
      DEFAULT_LIMIT = 50

      attr_reader :organization, :events, :offset, :limit

      def process_params
        @extid  = sanitize_identifier(params['extid'])
        @offset = [params['offset'].to_i, 0].max
        @limit  = params['limit'].nil? ? DEFAULT_LIMIT : params['limit'].to_i.clamp(1, 200)
      end

      def raise_concerns
        verify_authenticated!

        if @extid.to_s.empty?
          raise_form_error(
            error_key: 'api.organizations.errors.extid_required',
            field: :extid,
            error_type: :missing,
          )
        end

        @organization = load_organization(@extid)

        # Membership + plan gate in one: materialized entitlements are the
        # org plan ∩ role grants, so this admits only admins/owners of orgs
        # whose plan includes audit logs.
        require_entitlement_in!(@organization, 'audit_logs')
      end

      def process
        @events = organization.secret_activity_events_page(offset: offset, limit: limit)
        @actors = resolve_actors(@events)

        success_data
      end

      def success_data
        {
          user_id: cust.extid,
          organization_id: organization.extid,
          records: events,
          count: events.size,
          total: organization.secret_activity_event_count,
          details: {
            offset: offset,
            limit: limit,
            actors: @actors,
          },
        }
      end

      private

      # Read-time actor resolution (never written back into the trail — the
      # trail stays email-free for GDPR minimization). Only currently-active
      # members resolve; everything else stays out of the map so the UI
      # falls back to the raw objid, matching CloudTrail's deleted-principal
      # semantics. Best-effort per actor: one bad record must not 500 the
      # page.
      def resolve_actors(events)
        actor_ids = events.map { |ev| ev['actor_id'] }.reject { |id| id.to_s.empty? }.uniq

        actor_ids.each_with_object({}) do |actor_id, map|
          membership = Onetime::OrganizationMembership.find_by_org_customer(organization.objid, actor_id)
          next unless membership&.active?

          customer = membership.customer
          next unless customer

          map[actor_id] = { 'email' => customer.email, 'extid' => customer.extid }
        rescue StandardError => ex
          OT.le '[ListSecretActivity] actor resolution failed',
            organization: organization.objid,
            actor_id: actor_id,
            error: ex.message
        end
      end
    end
  end
end
