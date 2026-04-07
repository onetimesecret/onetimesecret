# apps/api/organizations/cli/add_member_command.rb
#
# frozen_string_literal: true

# CLI command for adding a member to an organization.
#
# Usage:
#   bin/ots organizations add-member --org ORG_ID --email EMAIL
#   bin/ots organizations add-member --org ORG_ID --email EMAIL --role admin
#   bin/ots organizations add-member --org ORG_ID --email EMAIL --default
#   bin/ots organizations add-member --org ORG_ID --email EMAIL --dry-run
#   bin/ots organizations add-member --org ORG_ID --email EMAIL --verbose
#
# The --org option accepts:
#   - Organization extid (e.g., on9c6g202oqnpvewujyhgjzhtz0)
#   - Custom domain hostname (e.g., secrets.company.com)
#
# The --default flag sets this organization as the customer's default,
# which determines which org is active when they log in.
#

module Onetime
  module CLI
    # Add a member to an organization
    class OrganizationsAddMemberCommand < Command
      desc 'Add a customer to an organization as a member'

      option :org,
        type: :string,
        required: true,
        desc: 'Organization identifier (extid) or custom domain hostname'

      option :email,
        type: :string,
        required: true,
        desc: 'Customer email address'

      option :role,
        type: :string,
        default: 'member',
        desc: 'Membership role: member or admin (default: member)'

      option :default,
        type: :boolean,
        default: false,
        desc: "Set this organization as the customer's default organization"

      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Preview changes without applying them'

      option :verbose,
        type: :boolean,
        default: false,
        desc: 'Show additional detail'

      VALID_ROLES = %w[member admin].freeze

      def call(org:, email:, role: 'member', default: false, dry_run: false, verbose: false, **)
        boot_application!

        @verbose = verbose
        @dry_run = dry_run

        validate_role!(role)
        organization   = find_organization!(org)
        customer       = find_customer!(email)
        pending_invite = warn_pending_invitation(organization, email)

        return if handle_existing_member(organization, customer, default)
        return if output_dry_run(organization, customer, role, default, pending_invite)

        add_member_and_verify(organization, customer, role, default)
      end

      private

      def validate_role!(role)
        return if VALID_ROLES.include?(role)

        puts "Error: Invalid role '#{role}'. Must be one of: #{VALID_ROLES.join(', ')}"
        exit 1
      end

      def find_organization!(org_identifier)
        organization = resolve_organization(org_identifier)
        unless organization
          puts "Error: Organization not found: #{org_identifier}"
          puts '  Tried: extid lookup, then domain hostname lookup'
          exit 1
        end

        log "Found organization: #{organization.display_name} (#{organization.extid})"
        organization
      end

      def find_customer!(email)
        customer = Onetime::Customer.find_by_email(OT::Utils.normalize_email(email))
        unless customer
          puts "Error: Customer not found with email: #{email}"
          puts '  The customer must have an existing account before being added to an organization.'
          exit 1
        end

        log "Found customer: #{OT::Utils.obscure_email(customer.email)} (#{customer.extid})"
        customer
      end

      def warn_pending_invitation(organization, email)
        pending_invite = check_pending_invitation(organization, email)
        return nil unless pending_invite

        puts "Warning: Pending invitation exists for #{email} to this organization"
        puts "  Invitation ID: #{pending_invite.objid}"
        puts "  Invited at: #{Time.at(pending_invite.invited_at.to_f).utc}" if pending_invite.invited_at
        puts "  Status: #{pending_invite.status}"
        puts
        puts '  Adding as member will bypass the invitation flow.'
        puts
        pending_invite
      end

      def handle_existing_member(organization, customer, set_default)
        return false unless organization.member?(customer)

        membership   = Onetime::OrganizationMembership.find_by_org_customer(organization.objid, customer.objid)
        current_role = membership&.role || 'unknown'

        puts "Customer is already a member of this organization (role: #{current_role})"

        if set_default
          handle_set_default(customer, organization)
        else
          puts 'No changes made. Use --default to set this as their default organization.'
        end
        true
      end

      def output_dry_run(organization, customer, role, set_default, pending_invite)
        return false unless @dry_run

        puts
        puts '=== DRY RUN ==='
        puts "Would add #{OT::Utils.obscure_email(customer.email)} to #{organization.display_name}"
        puts "  Role: #{role}"
        puts "  Set as default: #{set_default ? 'yes' : 'no'}"
        puts '  Note: Existing pending invitation would remain (not auto-revoked)' if pending_invite
        puts '==============='
        true
      end

      def add_member_and_verify(organization, customer, role, set_default)
        puts "Adding #{OT::Utils.obscure_email(customer.email)} to #{organization.display_name} as #{role}..."

        membership = organization.add_members_instance(customer, through_attrs: { role: role })

        unless membership
          puts 'Error: Failed to create membership record'
          exit 1
        end

        puts "Success: Member added with role '#{role}'"
        log "  Membership ID: #{membership.objid}"
        log "  Joined at: #{Time.at(membership.joined_at.to_f).utc}" if membership.joined_at

        handle_set_default(customer, organization) if set_default
        output_verification(organization, customer, set_default)
      end

      def output_verification(organization, customer, set_default)
        puts
        puts 'Verification:'
        puts "  Is member: #{organization.member?(customer)}"
        puts "  Member count: #{organization.member_count}"

        if set_default
          status = customer.default_org_id == organization.objid ? 'set correctly' : 'NOT SET (check logs)'
          puts "  Customer default org: #{status}"
        end

        output_member_list(organization) if @verbose
      end

      def output_member_list(organization)
        puts
        puts 'Organization members:'
        organization.list_members.each do |member|
          m = Onetime::OrganizationMembership.find_by_org_customer(organization.objid, member.objid)
          puts "  - #{OT::Utils.obscure_email(member.email)} (#{m&.role || 'unknown'})"
        end
      end

      def resolve_organization(identifier)
        # Try extid first
        org = Onetime::Organization.find_by_extid(identifier)
        return org if org

        log "Not found by extid, trying domain hostname: #{identifier}"

        # Try domain hostname
        domain = Onetime::CustomDomain.from_display_domain(identifier)
        return nil unless domain

        log "Found domain: #{domain.display_domain}"
        domain.primary_organization
      end

      def check_pending_invitation(organization, email)
        invite = Onetime::OrganizationMembership.find_by_org_email(organization.objid, email.to_s.strip.unicode_normalize(:nfc).downcase(:fold))
        return nil unless invite&.pending?

        invite
      end

      def handle_set_default(customer, organization)
        if @dry_run
          puts "Would set #{organization.display_name} as default for #{OT::Utils.obscure_email(customer.email)}"
          return
        end

        # Set the customer's default organization
        customer.default_org_id = organization.objid
        customer.save

        puts "Set #{organization.display_name} as default organization for #{OT::Utils.obscure_email(customer.email)}"
        log "  default_org_id: #{customer.default_org_id}"
      end

      def log(message)
        puts message if @verbose
      end
    end
  end
end

Onetime::CLI.register 'organizations add-member', Onetime::CLI::OrganizationsAddMemberCommand
