# frozen_string_literal: true

# CustomDomain Migration: custid → org_id
#
# This migration script is NOT needed because the code migration (adding org_id field,
# participates_in, etc.) handles the transition. This file is kept as documentation
# of migration logic for reference.
#
# MIGRATION LOGIC (for reference):
#
# 1. Pre-migration validation:
#    - Ensure all customers have at least one organization
#    - Count total domains to migrate
#    - Identify orphaned domains (invalid custid)
#
# 2. Migration process:
#    - For each CustomDomain:
#      a. Skip if already has org_id and participates in org
#      b. Find customer's organization via custid
#      c. Set domain.org_id = org.objid
#      d. Call domain.add_to_organization_domains(org)
#
# 3. Post-migration validation:
#    - All domains have org_id set
#    - All domains participate in exactly one organization
#    - All organizations have correct domain counts
#
# 4. Edge cases:
#    - Orphaned domains (custid doesn't match any customer)
#    - Customers without organizations (create default org)
#    - Duplicate domains (manual resolution)
#
# DATA GENERATOR:
#   See custom_domains_to_orgs_data_generator.rb for test data generation
#
# ORIGINAL IMPLEMENTATION (commented out):
#
# require_relative '../../lib/onetime/migration/model_migration'
#
# module Onetime
#   module Migration
#     class CustomDomainsToOrgs < ModelMigration
#       # Migration metadata
#       VERSION = '2025-01-07-001'
#       DESCRIPTION = 'Migrate CustomDomain from custid to org_id ownership'
#
#       # === Configuration ===
#
#       def prepare
#         @model_class = Onetime::CustomDomain
#         @batch_size = 100
#       end
#
#       # === Pre-migration validation ===
#
#       def migration_needed?
#         # Check if there are any domains without org_id
#         domains_without_org_id = CustomDomain.all.select { |d| d.org_id.nil? || d.org_id.to_s.empty? }
#
#         if domains_without_org_id.empty?
#           info('[Migration] All domains already have org_id - migration not needed')
#           return false
#         end
#
#         info("[Migration] Found #{domains_without_org_id.size} domains without org_id")
#
#         # Validate preconditions before proceeding
#         validate_preconditions
#
#         true
#       end
#
#       # === Core migration logic ===
#
#       # Process a single custom domain record
#       #
#       # Migration steps for each domain:
#       # 1. Skip if already migrated (has org_id and participates in org)
#       # 2. Find customer's default organization
#       # 3. Set org_id foreign key
#       # 4. Add domain to organization via participation
#       #
#       # @param domain [CustomDomain] The domain to migrate
#       # @param key [String] The Redis key for this domain
#       def process_record(domain, key)
#         # Skip if already migrated
#         if already_migrated?(domain)
#           track_stat(:skipped)
#           debug("Skipped (already migrated): #{domain.display_domain}")
#           return
#         end
#
#         # Find customer's organization
#         org = find_organization_for_domain(domain)
#
#         unless org
#           track_stat(:orphaned)
#           error("Orphaned domain (no organization found): #{domain.display_domain} custid=#{domain.custid}")
#           return
#         end
#
#         # Perform migration
#         if migrate_domain_to_organization(domain, org)
#           track_stat(:migrated)
#         else
#           track_stat(:failed)
#         end
#       end
#
#       private
#
#       # === Validation methods ===
#
#       def validate_preconditions
#         info('[Migration] Validating preconditions...')
#
#         # Check: All customers should have at least one organization
#         customers_without_orgs = find_customers_without_organizations
#
#         if customers_without_orgs.any?
#           error("[Migration] ERROR: #{customers_without_orgs.size} customers lack organizations")
#           error('[Migration] Customer IDs without organizations:')
#           customers_without_orgs.first(10).each do |cust|
#             error("  - #{cust.custid} (#{cust.email})")
#           end
#           raise Onetime::Problem, "#{customers_without_orgs.size} customers lack organizations"
#         end
#
#         # Count domains to migrate
#         total_domains = CustomDomain.all.size
#         info("[Migration] Found #{total_domains} total domains")
#         info('[Migration] Preconditions validated successfully')
#
#         true
#       end
#
#       # === Migration helper methods ===
#
#       # Check if a domain has already been migrated
#       #
#       # A domain is considered migrated if:
#       # 1. Has org_id field set
#       # 2. Participates in at least one organization
#       #
#       # @param domain [CustomDomain] The domain to check
#       # @return [Boolean] true if already migrated
#       def already_migrated?(domain)
#         has_org_id = domain.org_id && !domain.org_id.to_s.empty?
#         has_participation = domain.organization_instances.any?
#
#         has_org_id && has_participation
#       end
#
#       # Find the organization that should own this domain
#       #
#       # Strategy:
#       # 1. Find customer by custid
#       # 2. Get customer's default organization (or first org if no default)
#       #
#       # @param domain [CustomDomain] The domain to find organization for
#       # @return [Organization, nil] The organization or nil if not found
#       def find_organization_for_domain(domain)
#         return nil unless domain.custid
#
#         # Find customer by custid
#         customer = Customer.find_by_email(domain.custid)
#         return nil unless customer
#
#         # Get customer's organizations
#         orgs = customer.organization_instances
#
#         return nil if orgs.empty?
#
#         # Try to find default organization first
#         default_org = orgs.find { |org| org.is_default.to_s == 'true' }
#         default_org || orgs.first
#       end
#
#       # Migrate a domain to an organization
#       #
#       # Steps:
#       # 1. Set org_id foreign key
#       # 2. Save domain with new org_id
#       # 3. Add to organization via participation
#       #
#       # @param domain [CustomDomain] The domain to migrate
#       # @param org [Organization] The organization to migrate to
#       # @return [Boolean] true if successful, false otherwise
#       def migrate_domain_to_organization(domain, org)
#         for_realsies_this_time? do
#           # Set org_id foreign key (use objid NOT the org object)
#           domain.org_id = org.objid
#
#           # Save domain with new org_id
#           domain.save
#
#           # Add to organization via participation
#           domain.add_to_organization_domains(org)
#         end
#
#         info("Migrated: #{domain.display_domain} -> org #{org.objid} (#{org.display_name})")
#         true
#       rescue StandardError => e
#         error("Failed to migrate #{domain.display_domain}: #{e.message}")
#         error("Stack trace: #{e.backtrace.first(5).join('; ')}")
#         false
#       end
#
#       # === Query methods ===
#
#       def find_customers_without_organizations
#         Customer.all.select { |c| c.organization_instances.empty? }
#       end
#
#       # === Statistics reporting ===
#
#       def print_migration_summary
#         super # Call parent to get standard stats
#
#         # Add custom statistics
#         print_summary('Migration Summary') do
#           info('')
#           info('Migration statistics:')
#           info("  Migrated: #{@stats[:migrated]}")
#           info("  Skipped (already migrated): #{@stats[:skipped]}")
#           info("  Orphaned (no organization): #{@stats[:orphaned]}")
#           info("  Failed: #{@stats[:failed]}")
#
#           # Validation recommendation
#           if actual_run? && @stats[:failed] == 0
#             info('')
#             info('Next steps:')
#             info('  1. Verify migration with: bin/ots migrate validate_custom_domains.rb')
#             info('  2. Check application logs for any domain-related errors')
#           end
#         end
#       end
#     end
#   end
# end
#
# # Register migration class with the framework
# # This allows the migrate command to discover and run it
# module Onetime
#   module Migration
#     def self.run(options = {})
#       CustomDomainsToOrgs.run(options)
#     end
#   end
# end

# Empty module for namespace consistency
module Onetime
  module Migration
    # Migration implementation moved to comment above
  end
end
