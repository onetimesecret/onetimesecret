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
        :status, :customer_extid, :email_obscured, :organization_extid,
        :personal_org_extid, :message,
        keyword_init: true,
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

      # Find all customers eligible for migration.
      #
      # Eligible: email domain matches the custom domain's base domain,
      # AND customer is NOT already a member of the domain organization.
      #
      # @yield [scanned, total] Progress callback
      # @return [Array<Onetime::Customer>] eligible customers
      def find_eligible_customers(&progress)
        email_suffix = "@#{domain.base_domain}"
        candidates   = []
        all_customers = Onetime::Customer.instances.to_a
        total         = all_customers.size

        all_customers.each_with_index do |objid, idx|
          progress&.call(idx + 1, total)

          customer = Onetime::Customer.load(objid)
          next unless customer
          next if customer.email.to_s.empty?
          next unless customer.email.downcase.end_with?(email_suffix)
          next if organization.member?(customer)

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
          return Result.new(
            status: :skipped_already_member,
            customer_extid: customer.extid,
            email_obscured: obscured,
            organization_extid: organization.extid,
            message: 'Already a member of domain organization',
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

        if personal_org && personal_org.objid != organization.objid
          personal_org.archive!
          OT.info "[BulkSsoMigration] Archived personal workspace #{personal_org.extid} for #{customer.extid}"
        end

        OT.info "[BulkSsoMigration] Migrated #{customer.extid} to #{organization.extid} (domain: #{domain.display_domain})"

        Result.new(
          status: :migrated,
          customer_extid: customer.extid,
          email_obscured: obscured,
          organization_extid: organization.extid,
          personal_org_extid: personal_org&.extid,
          message: 'Migrated successfully',
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

          membership = Onetime::OrganizationMembership.find_by_org_customer(org.objid, customer.objid)
          next unless membership&.owner?
          next if membership.domain_scope_id.to_s.length > 0

          org
        end.first
      end
    end
  end
end
