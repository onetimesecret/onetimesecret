# apps/api/organizations/cli/list_command.rb
#
# CLI command for listing and inspecting organizations.
#
# Usage:
#   bin/ots organizations                           # List all organizations
#   bin/ots organizations --extid on9c6...         # Show specific org by extid
#   bin/ots organizations --customer cus_xxx       # Find org by Stripe customer ID
#   bin/ots organizations --subscription sub_xxx   # Find org by Stripe subscription ID
#
# frozen_string_literal: true

module Onetime
  module CLI
    # Main organizations command (list/show)
    class OrganizationsListCommand < Command
      desc 'List organizations or show details by ID'

      option :extid,
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

      option :limit,
        type: :integer,
        default: 50,
        desc: 'Maximum organizations to list'

      def call(extid: nil, customer: nil, subscription: nil, owner: nil, limit: 50, **)
        boot_application!

        # Single org lookup modes
        if extid
          show_organization_by_extid(extid)
        elsif customer
          show_organization_by_stripe_customer(customer)
        elsif subscription
          show_organization_by_stripe_subscription(subscription)
        else
          list_organizations(owner: owner, limit: limit)
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
      end

      def list_organizations(owner: nil, limit: 50)
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
        end

        if all_org_ids.size > limit
          puts
          puts "(showing #{limit} of #{all_org_ids.size} - use --limit to see more)"
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
