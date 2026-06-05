# apps/web/auth/operations/bulk_sso_migration.rb
#
# frozen_string_literal: true

module Auth
  module Operations
    # Migrates legacy install-level SSO users to a domain organization.
    #
    # When a customer switches from install-level SSO to domain-level SSO,
    # users who previously signed in retain independent owner accounts with
    # personal default workspaces. This operation bulk-migrates them into
    # the domain's organization.
    #
    # Eligibility (all must be true):
    #   - Email domain matches the custom domain's base domain
    #   - Not already a member of the domain organization
    #   - Provisioned via SSO (provisioning_origin: 'sso_jit' or nil for legacy)
    #   - Owns a personal default workspace (structural fingerprint of
    #     install-level SSO — CreateDefaultWorkspace ran instead of
    #     JoinDomainOrganization)
    #
    # Self-signup users (canonical_signup, domain_signup) and invited users
    # are never affected.
    #
    # For each eligible user:
    #   1. Calls JoinDomainOrganization (reuses existing SSO join logic)
    #   2. Repoints customer.default_org_id to the domain org
    #   3. Soft-archives the personal workspace (sets archived_at, preserves data)
    #
    # Idempotent: already-migrated users are skipped.
    # Supports dry-run mode for auditing before execution.
    #
    class BulkSsoMigration
      include Onetime::LoggerMethods

      Result = Struct.new(
        :status,
        :customer_extid,
        :email_obscured,
        :organization_extid,
        :personal_org_extid,
        :message,
        keyword_init: true
      )

      attr_reader :domain, :organization, :dry_run

      # @param domain [Onetime::CustomDomain] The custom domain to migrate users into
      # @param dry_run [Boolean] When true, reports what would happen without making changes
      def initialize(domain:, dry_run: true)
        @domain   = domain
        @dry_run  = dry_run

        @organization = domain.primary_organization
        raise Onetime::Problem, "Domain #{domain.display_domain} has no primary organization" unless @organization
      end

      # Provisioning origins eligible for bulk SSO migration.
      # Only nil/empty (legacy install-level accounts) and sso_jit are migrated;
      # all other origins (self-signup, invite, future methods) are excluded.
      ELIGIBLE_ORIGINS = [nil, '', 'sso_jit'].freeze

      # Find all customers eligible for migration.
      #
      # Eligible: email domain matches, not already a member, SSO-provisioned
      # (or legacy nil origin), and owns a personal default workspace.
      #
      # @yield [scanned, total] Progress callback
      # @return [Array<Onetime::Customer>] eligible customers
      def find_eligible_customers(&progress)
        base = domain.base_domain.to_s.downcase
        raise Onetime::Problem, "Domain #{domain.display_domain} has no base_domain — cannot match emails" if base.empty?

        email_suffix  = "@#{base}"
        candidates    = []
        all_customers = Onetime::Customer.instances.to_a
        total         = all_customers.size

        all_customers.each_with_index do |objid, idx|
          progress&.call(idx + 1, total)

          customer = Onetime::Customer.load(objid)
          next unless customer
          next if customer.email.to_s.empty?
          next unless customer.email.downcase.end_with?(email_suffix)
          next unless ELIGIBLE_ORIGINS.include?(customer.provisioning_origin)

          if organization.member?(customer)
            next unless needs_repair?(customer)
          else
            next unless find_personal_workspace(customer)
          end

          candidates << customer
        end

        candidates
      end

      # Migrate a single customer into the domain organization.
      #
      # @param customer [Onetime::Customer] The customer to migrate
      # @return [Result] Outcome of the migration attempt
      def migrate_customer(customer)
        obscured = OT::Utils.obscure_email(customer.email)

        if organization.member?(customer)
          if dry_run
            repair_needed = needs_repair?(customer)
            status = repair_needed ? :would_repair : :skipped_already_member
            message = repair_needed ? 'Would repair partial migration state' : 'Already a member of domain organization'
          else
            repair_needed = needs_repair?(customer)
            repaired = false
            repaired |= repair_default_org!(customer)
            repaired |= repair_archive!(customer)

            if repaired
              status = :repaired
              message = 'Already a member; repaired partial migration state'
            elsif repair_needed
              status = :error
              message = 'Repair needed but all repair attempts failed'
            else
              status = :skipped_already_member
              message = 'Already a member of domain organization'
            end
          end

          return Result.new(
            status: status,
            customer_extid: customer.extid,
            email_obscured: obscured,
            organization_extid: organization.extid,
            message: message,
          )
        end

        personal_org = find_personal_workspace(customer)

        if dry_run
          return Result.new(
            status: :would_migrate,
            customer_extid: customer.extid,
            email_obscured: obscured,
            organization_extid: organization.extid,
            personal_org_extid: personal_org&.extid,
            message: 'Would migrate',
          )
        end

        join_result = Auth::Operations::JoinDomainOrganization.new(
          customer: customer,
          domain_id: domain.objid,
        ).call

        unless join_result[:joined] || join_result[:reason] == 'already_member'
          return Result.new(
            status: :error,
            customer_extid: customer.extid,
            email_obscured: obscured,
            message: "Join failed: #{join_result[:reason]}",
          )
        end

        customer.default_org_id = organization.objid
        customer.save

        archive_failed = false
        if personal_org && personal_org.objid != organization.objid
          begin
            personal_org.archive!("Bulk SSO migration to #{domain.display_domain}")
            OT.info "[BulkSsoMigration] Archived personal workspace #{personal_org.extid} for #{customer.extid}"
          rescue StandardError => ex
            archive_failed = true
            OT.le "[BulkSsoMigration] Joined org but failed to archive personal workspace #{personal_org.extid} for #{customer.extid}: #{ex.message}"
          end
        end

        status  = archive_failed ? :migrated_archive_failed : :migrated
        message = archive_failed ? 'Joined domain org but personal workspace archival failed' : 'Migrated successfully'

        OT.info "[BulkSsoMigration] Migrated #{customer.extid} to #{organization.extid} (domain: #{domain.display_domain})"

        Result.new(
          status: status,
          customer_extid: customer.extid,
          email_obscured: obscured,
          organization_extid: organization.extid,
          personal_org_extid: personal_org&.extid,
          message: message,
        )
      rescue StandardError => ex
        OT.le "[BulkSsoMigration] Error migrating #{customer.extid}: #{ex.message}"
        Result.new(
          status: :error,
          customer_extid: customer.extid,
          email_obscured: obscured,
          message: ex.message,
        )
      end

      private

      # Repair default_org_id if it doesn't point to the domain org.
      # Handles the case where a prior run joined the org but customer.save
      # failed before default_org_id was persisted.
      # @return [Boolean] true if a repair was made
      def repair_default_org!(customer)
        return false if customer.default_org_id == organization.objid

        customer.default_org_id = organization.objid
        customer.save
        OT.info "[BulkSsoMigration] Repaired default_org_id for #{customer.extid} -> #{organization.extid}"
        true
      rescue StandardError => ex
        OT.le "[BulkSsoMigration] Failed to repair default_org_id for #{customer.extid}: #{ex.message}"
        false
      end

      # Archive a personal workspace that a prior run failed to archive.
      # @return [Boolean] true if a repair was made
      def repair_archive!(customer)
        personal_org = find_personal_workspace(customer)
        return false unless personal_org

        personal_org.archive!("Bulk SSO migration to #{domain.display_domain}")
        OT.info "[BulkSsoMigration] Repaired: archived personal workspace #{personal_org.extid} for #{customer.extid}"
        true
      rescue StandardError => ex
        OT.le "[BulkSsoMigration] Failed to repair archive for #{customer.extid}: #{ex.message}"
        false
      end

      # Find a customer's personal default workspace (the one created by
      # CreateDefaultWorkspace during install-level SSO).
      #
      # Characteristics: is_default=true, customer is owner, no domain_scope_id
      # on the membership.
      def find_personal_workspace(customer)
        customer.organization_instances.to_a.filter_map do |org_objid|
          org = Onetime::Organization.load(org_objid)
          next unless org
          next unless org.is_default.to_s == 'true'
          next if org.objid == organization.objid
          next if org.archived?

          membership = Onetime::OrganizationMembership.find_by_org_customer(org.objid, customer.objid)
          next unless membership&.owner?
          next unless membership.domain_scope_id.to_s.empty?

          org
        end.first
      end

      def needs_repair?(customer)
        return true if customer.default_org_id != organization.objid
        return true if find_personal_workspace(customer)

        false
      end
    end
  end
end
