# apps/api/organizations/cli/list_command.rb
#
# frozen_string_literal: true

# CLI command for listing and inspecting organizations.
#
# Usage:
#   bin/ots organizations --list                         # List all organizations
#   bin/ots organizations --list --verbose               # List with members and domains
#   bin/ots organizations --show EXTID                   # Show specific org by extid
#   bin/ots organizations --customer cus_xxx             # Find org by Stripe customer ID
#   bin/ots organizations --subscription sub_xxx         # Find org by Stripe subscription ID
#   bin/ots organizations --check                        # Check for inconsistencies
#

module Onetime
  module CLI
    # Main organizations command (list/show/check)
    class OrganizationsListCommand < Command
      desc 'Manage organization records (list, show, check)'

      option :list,
        type: :boolean,
        default: false,
        desc: 'List all organizations'

      option :show,
        type: :string,
        default: nil,
        desc: 'Show organization by external ID (e.g., on9c6g202oqnpvewujyhgjzhtz0)'

      option :customer,
        type: :string,
        default: nil,
        desc: 'Find organization by Stripe customer ID (cus_xxx)'

      option :subscription,
        type: :string,
        default: nil,
        desc: 'Find organization by Stripe subscription ID (sub_xxx)'

      option :owner,
        type: :string,
        default: nil,
        desc: 'Filter by owner email'

      option :check,
        type: :boolean,
        default: false,
        desc: 'Check for organizations with missing owners or orphaned records'

      option :verbose,
        type: :boolean,
        default: false,
        desc: 'Show additional detail (member lists, domains)'

      option :limit,
        type: :integer,
        default: 50,
        desc: 'Maximum organizations to list'

      def call(list: false, show: nil, customer: nil, subscription: nil, owner: nil, check: false, verbose: false, limit: 50, **)
        boot_application!

        if show
          show_organization_by_extid(show)
        elsif customer
          show_organization_by_stripe_customer(customer)
        elsif subscription
          show_organization_by_stripe_subscription(subscription)
        elsif check
          check_organizations
        elsif list
          list_organizations(owner: owner, limit: limit, verbose: verbose)
        else
          puts format('%d organizations', Onetime::Organization.count)
          puts "\nUsage:"
          puts '  bin/ots organizations --list                    # List all organizations'
          puts '  bin/ots organizations --list --verbose          # List with members and domains'
          puts '  bin/ots organizations --show EXTID              # Show organization details'
          puts '  bin/ots organizations --customer cus_xxx        # Find by Stripe customer'
          puts '  bin/ots organizations --subscription sub_xxx    # Find by Stripe subscription'
          puts '  bin/ots organizations --check                   # Check for inconsistencies'
        end
      end

      private

      def show_organization_by_extid(extid)
        org = Onetime::Organization.find_by_extid(extid)
        if org.nil?
          puts "Organization not found: #{extid}"
          exit 1
        end
        display_organization_details(org)
      end

      def show_organization_by_stripe_customer(customer_id)
        org = Onetime::Organization.find_by_stripe_customer_id(customer_id)
        if org.nil?
          puts "No organization found with Stripe customer: #{customer_id}"
          exit 1
        end
        display_organization_details(org)
      end

      def show_organization_by_stripe_subscription(subscription_id)
        org = Onetime::Organization.find_by_stripe_subscription_id(subscription_id)
        if org.nil?
          puts "No organization found with Stripe subscription: #{subscription_id}"
          exit 1
        end
        display_organization_details(org)
      end

      def display_organization_details(org)
        puts
        puts '=' * 60
        puts "Organization: #{org.display_name}"
        puts '=' * 60
        puts
        puts "  External ID:       #{org.extid}"
        puts "  Internal ID:       #{org.objid}"
        puts "  Owner ID:          #{org.owner_id}"
        puts "  Owner Email:       #{owner_email(org)}"
        puts "  Contact Email:     #{org.contact_email}"
        puts "  Is Default:        #{org.is_default}"
        puts
        puts 'Billing:'
        puts "  Plan ID:           #{org.planid}"
        puts "  Stripe Customer:   #{org.stripe_customer_id || '(none)'}"
        puts "  Stripe Subscription: #{org.stripe_subscription_id || '(none)'}"
        puts "  Subscription Status: #{org.subscription_status || '(none)'}"
        puts
        puts 'Counts:'
        puts "  Members:           #{org.member_count}"
        puts "  Domains:           #{org.domain_count}"
        puts "  Pending Invites:   #{org.pending_invitation_count}"
        puts

        if org.member_count > 0
          puts 'Members:'
          org.list_members.each do |member|
            puts "  - #{OT::Utils.obscure_email(member.custid)}"
          end
          puts
        end

        return unless org.domain_count > 0

        puts 'Domains:'
        org.list_domains.each do |domain|
          puts "  - #{domain.display_domain}  (state: #{domain.verification_state})"
        end
        puts
      end

      def list_organizations(owner: nil, limit: 50, verbose: false)
        all_org_ids = Onetime::Organization.instances.all
        puts format('%d total organizations', all_org_ids.size)
        puts

        orgs = all_org_ids.take(limit).map do |oid|
          Onetime::Organization.load(oid)
        end.compact

        # Filter by owner if specified
        if owner
          orgs = orgs.select do |org|
            owner_cust = org.owner
            next false unless owner_cust&.email

            owner_cust.email.downcase.include?(owner.downcase)
          end
          puts format('Filtered to %d organizations owned by "%s"', orgs.size, owner)
          puts
        end

        return if orgs.empty?

        # Table header
        puts format(
          '%-32s %-20s %-20s %-18s',
          'ExtID',
          'Display Name',
          'Plan',
          'Stripe Customer',
        )
        puts '-' * 95

        orgs.each do |org|
          display_name = truncate(org.display_name.to_s, 18)
          plan         = org.planid.to_s.empty? ? 'free' : truncate(org.planid.to_s, 18)
          stripe_cust  = org.stripe_customer_id.to_s.empty? ? '-' : org.stripe_customer_id

          puts format(
            '%-32s %-20s %-20s %-18s',
            org.extid,
            display_name,
            plan,
            stripe_cust,
          )

          next unless verbose

          if org.member_count > 0
            org.list_members.each do |member|
              puts format('    member: %s', OT::Utils.obscure_email(member.custid))
            end
          end

          next unless org.domain_count > 0

          org.list_domains.each do |domain|
            puts format('    domain: %s  state=%s', domain.display_domain, domain.verification_state)
          end
        end

        if all_org_ids.size > limit
          puts
          puts "(showing #{limit} of #{all_org_ids.size} - use --limit to see more)"
        end
      end

      def check_organizations
        count = Onetime::Organization.count
        puts format('%d organizations', count)
        puts

        issues = []

        all_org_ids = Onetime::Organization.instances.all
        all_orgs    = all_org_ids.filter_map do |objid|
          Onetime::Organization.load(objid)
        rescue Familia::RecordNotFound
          issues << "Stale instance reference: #{objid} (record not found)"
          nil
        end

        all_orgs.each do |org|
          # Check for missing owner
          if org.owner_id.to_s.empty?
            issues << "#{org.extid} (#{org.display_name}): no owner_id set"
          else
            owner = Onetime::Customer.load(org.owner_id)
            if owner.nil?
              issues << "#{org.extid} (#{org.display_name}): owner_id references missing customer #{OT::Utils.obscure_email(org.owner_id)}"
            end
          end

          # Check for empty display_name
          if org.display_name.to_s.strip.empty?
            issues << "#{org.extid}: empty display_name"
          end

          # Check member count vs actual loadable members
          raw_count = org.members.size
          loaded    = org.list_members
          if raw_count != loaded.size
            issues << "#{org.extid} (#{org.display_name}): member count mismatch (index: #{raw_count}, loadable: #{loaded.size})"
          end
        end

        if issues.empty?
          puts 'All organizations are consistent.'
        else
          puts format('%d issues found:', issues.size)
          puts
          issues.each { |issue| puts "  - #{issue}" }
        end
      end

      def owner_email(org)
        owner = org.owner
        return '(unknown)' unless owner

        OT::Utils.obscure_email(owner.email.to_s)
      end

      def truncate(str, max_length)
        return str if str.length <= max_length

        "#{str[0, max_length - 1]}…"
      end
    end
  end
end

Onetime::CLI.register 'organizations', Onetime::CLI::OrganizationsListCommand
Onetime::CLI.register 'organization', Onetime::CLI::OrganizationsListCommand
