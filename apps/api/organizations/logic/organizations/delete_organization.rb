# apps/api/organizations/logic/organizations/delete_organization.rb
#
# frozen_string_literal: true

# Loaded at the call site, mirroring ColonelAPI::Logic::Colonel::RepairDomain.
require 'onetime/operations/domains/repair'

module OrganizationAPI::Logic
  module Organizations
    # Delete Organization
    #
    # @api Permanently deletes an organization. Only the organization owner
    #   can perform this action. Returns a confirmation of deletion.
    #
    # Organization#destroy! owns ALL of the teardown (member participations,
    # pending invitations, the global instances registry entry) inside its
    # guarded path — this logic deliberately performs NO pre-destroy
    # mutations, so a guard refusal leaves the org fully intact.
    class DeleteOrganization < OrganizationAPI::Logic::Base
      SCHEMAS = { response: 'organizationDelete' }.freeze

      attr_reader :organization

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        # Require authenticated user
        verify_authenticated!

        # Validate extid parameter
        if @extid.to_s.empty?
          raise_form_error(
            error_key: 'api.organizations.errors.extid_required',
            field: :extid,
            error_type: :missing,
          )
        end

        # Load organization
        @organization = load_organization(@extid)

        # Verify user has manage_org entitlement in this organization
        require_entitlement_in!(@organization, 'manage_org')

        # Refuse before doing anything when domains are attached. The model
        # guard in Organization#destroy! raises a bare Onetime::Problem, which
        # has no registered Otto error handler and surfaces as a 500 — this
        # form error is the request-safe 422 for the common refusal path; the
        # model guard stays as defense-in-depth.
        raise_domains_present_error if @organization.domain_count > 0
      end

      def process
        OT.ld "[DeleteOrganization] Deleting organization #{@extid} for user #{cust.extid}"

        # Get organization info before deletion
        objid        = @organization.objid
        display_name = @organization.display_name

        # Capture member contact info BEFORE destroy! removes the membership
        # records, so we can notify everyone once the organization is gone.
        members    = @organization.list_members
        recipients = members.filter_map do |member|
          next if member.email.to_s.empty?

          { email: member.email, locale: (member.respond_to?(:locale) ? member.locale : nil) }
        end

        # Self-heal drifted domain memberships (CustomDomain.owners attributes
        # the domain to this org but the org.domains sorted set lost it) via
        # the single audited repair implementation. Repaired domains land back
        # in org.domains — making them VISIBLE in the user's domain list — and
        # the re-check below then refuses the delete: repair-then-refuse,
        # never repair-then-delete.
        drifted    = @organization.unlisted_owned_domains
        unrepaired = repair_drifted_domains(drifted)

        # Re-check after the repair (raise_concerns already refused visible
        # domains; this covers repaired drift and races). Domains whose repair
        # FAILED are still invisible to the user, so they get the drift
        # message instead of "remove all domains first".
        raise_domains_present_error if @organization.domain_count > 0
        raise_domains_drifted_error(unrepaired) if unrepaired.any?

        # The single mutation point. Organization#destroy! removes member
        # participations, pending invitations (#2878), and the instances
        # registry entry (Familia 2.12 remove_from_instances!) inside its
        # guarded deletion path — if its guard raises, the org stays intact.
        @organization.destroy!

        OT.info "[DeleteOrganization] Deleted organization #{objid} (#{display_name})"

        notify_members_deleted(recipients, display_name)

        success_data
      end

      # Best-effort notification to former members that the organization was
      # deleted. Each send is isolated so one failure doesn't skip the rest,
      # and no failure may affect the (already-completed) deletion.
      def notify_members_deleted(recipients, display_name)
        recipients.each do |recipient|
          # Blank ("") locales are truthy and slip past a bare `||`; treat as missing.
          email_locale = recipient[:locale]
          email_locale = OT.default_locale if email_locale.to_s.strip.empty?
          Onetime::Jobs::Publisher.enqueue_email(
            :organization_deleted,
            {
              email_address: recipient[:email],
              organization_name: display_name,
              deleted_by: cust.email,
              deleted_at: Time.now.utc.iso8601,
              locale: email_locale,
            },
            fallback: :async_thread,
          )
        rescue StandardError => ex
          OT.le "[DeleteOrganization] Failed to send organization_deleted email: #{ex.message}"
        end
      end

      def success_data
        {
          user_id: cust.extid,
          deleted: true,
          extid: @extid,
        }
      end

      def form_fields
        {
          extid: @extid,
        }
      end

      private

      # Repair each drifted domain through Onetime::Operations::Domains::Repair
      # (the SINGLE audited repair implementation — one ColonelAuditEvent per
      # applied repair). No org: is passed, so the residual ORPHANED shape
      # (owners entry names this org but the record's org_id is blank — legacy
      # data only, CustomDomain#save raises on blank org_id) is deliberately
      # deferred to operator intent: the op returns :needs_org and mutates
      # nothing, which flows into the unrepairable-drift refusal pointing at
      # `bin/ots domains doctor --repair` (the doctor requires an explicit
      # --org decision for orphan repair). Assigning ownership from a stale
      # denormalized index alone, as a side effect of a user-initiated delete,
      # would be wrong. Each domain is isolated so one failed repair doesn't
      # abort the rest.
      #
      # @param drifted [Array<Onetime::CustomDomain>]
      # @return [Array<Onetime::CustomDomain>] domains that could NOT be repaired
      def repair_drifted_domains(drifted)
        drifted.reject do |domain|
          result = Onetime::Operations::Domains::Repair.new(
            domain: domain,
            actor: cust.extid, # acting user's PUBLIC id (never an objid)
            dry_run: false,
          ).call
          OT.info "[DeleteOrganization] Drift repair for #{domain.display_domain} " \
                  "on #{@extid}: status=#{result.status}"
          [:repaired, :no_issues].include?(result.status)
        rescue StandardError => ex
          OT.le '[DeleteOrganization] Failed to repair drifted domain ' \
                "#{domain.display_domain} for #{@extid}: #{ex.class}: #{ex.message}"
          false
        end
      end

      # Same wording as the Organization#destroy! guard, surfaced as a 422
      # form error instead of the guard's bare Onetime::Problem (which has no
      # Otto handler and would 500).
      def raise_domains_present_error
        raise_form_error(
          'Cannot delete organization with domains. Remove all domains first.',
          field: :extid,
          error_type: :has_domains,
        )
      end

      # Drifted domains whose repair failed are still invisible in the user's
      # domain list, so point at the operator repair path instead.
      def raise_domains_drifted_error(unrepaired)
        names = unrepaired.map(&:display_domain).join(', ')
        raise_form_error(
          "Cannot delete organization: domain records still reference it (#{names}). " \
          'Run bin/ots domains doctor --repair or remove the domains, then retry.',
          field: :extid,
          error_type: :has_domains,
        )
      end
    end
  end
end
