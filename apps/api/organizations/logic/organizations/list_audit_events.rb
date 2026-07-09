# apps/api/organizations/logic/organizations/list_audit_events.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Organizations
    # List Audit Events
    #
    # @api Returns a page of the organization's audit trail, newest first:
    #   secret creation, link/status fetches, reveals, burns and expiries
    #   recorded for receipts created in this organization's context
    #   (see Organization::Features::AuditTrail). Requires the `audit_logs`
    #   entitlement, which the role/plan intersection grants to admins and
    #   owners on plans that include it.
    #
    #   Event kinds: 'created' (secret concealed/generated), 'status_get'
    #   / 'secret_get' (a third party fetched the status/secret link),
    #   'previewed' (the creator opened their own secret link — the
    #   creator-facing "preview" event), 'creator_status_get' (the creator
    #   checked their own secret's status), 'receipt_viewed' (the creator's
    #   receipt/metadata page was loaded — distinct from opening the secret
    #   link itself), 'revealed', 'burned', 'expired', 'orphaned'. Events
    #   carry receipt/secret shortids only — never full identifiers, which
    #   are capability tokens.
    class ListAuditEvents < OrganizationAPI::Logic::Base
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
        @events = organization.audit_events_page(offset: offset, limit: limit)

        success_data
      end

      def success_data
        {
          user_id: cust.extid,
          organization_id: organization.extid,
          records: events,
          count: events.size,
          total: organization.audit_event_count,
          details: {
            offset: offset,
            limit: limit,
          },
        }
      end
    end
  end
end
