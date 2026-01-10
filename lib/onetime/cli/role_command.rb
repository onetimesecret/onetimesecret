# lib/onetime/cli/role_command.rb
#
# CLI command for managing customer roles. This replaces the legacy config-based
# colonel assignment with explicit role management via command line.
#
# Usage:
#   bin/ots role promote user@example.com              # Promote to colonel (default)
#   bin/ots role promote user@example.com --role admin # Promote to specific role
#   bin/ots role demote user@example.com               # Demote to customer
#   bin/ots role list                                  # List all colonels
#   bin/ots role list --role admin                     # List users with specific role
#
# frozen_string_literal: true

module Onetime
  module CLI
    class RoleCommand < Command
      desc 'Manage customer roles (promote, demote, list)'

      argument :action,
        type: :string,
        required: true,
        desc: 'Action to perform: promote, demote, or list'

      argument :email,
        type: :string,
        required: false,
        desc: 'Email address of the customer (required for promote/demote)'

      option :role,
        type: :string,
        default: 'colonel',
        desc: 'Target role for promotion or listing (colonel, admin, staff, customer)'

      option :force,
        type: :boolean,
        default: false,
        aliases: ['-f'],
        desc: 'Skip confirmation prompt'

      # Valid roles in hierarchy order (highest to lowest)
      VALID_ROLES = %w[colonel admin staff customer].freeze

      def call(action:, email: nil, role: 'colonel', force: false, **)
        boot_application!

        case action.downcase
        when 'promote'
          promote_customer(email, role, force)
        when 'demote'
          demote_customer(email, force)
        when 'list'
          list_customers_by_role(role)
        else
          puts "Unknown action: #{action}"
          puts 'Valid actions: promote, demote, list'
          exit 1
        end
      end

      private

      def promote_customer(email, target_role, force)
        validate_email_provided!(email, 'promote')
        validate_role!(target_role)

        customer = find_customer!(email)
        old_role = customer.role.to_s
        obscured = OT::Utils.obscure_email(email)

        if old_role == target_role
          puts "#{obscured} already has role '#{target_role}'"
          return
        end

        unless force
          print "Promote #{obscured} from '#{old_role}' to '#{target_role}'? [y/N] "
          response = $stdin.gets&.strip&.downcase
          unless response == 'y'
            puts 'Aborted.'
            return
          end
        end

        customer.role = target_role
        customer.save

        puts "#{obscured}: #{old_role} -> #{target_role}"
        OT.info "[role-change] #{customer.objid} promoted: #{old_role} -> #{target_role}"
      end

      def demote_customer(email, force)
        validate_email_provided!(email, 'demote')

        customer = find_customer!(email)
        old_role = customer.role.to_s
        obscured = OT::Utils.obscure_email(email)

        if old_role == 'customer'
          puts "#{obscured} already has role 'customer'"
          return
        end

        unless force
          print "Demote #{obscured} from '#{old_role}' to 'customer'? [y/N] "
          response = $stdin.gets&.strip&.downcase
          unless response == 'y'
            puts 'Aborted.'
            return
          end
        end

        customer.role = 'customer'
        customer.save

        puts "#{obscured}: #{old_role} -> customer"
        OT.info "[role-change] #{customer.objid} demoted: #{old_role} -> customer"
      end

      def list_customers_by_role(target_role)
        validate_role!(target_role)

        puts "Customers with role '#{target_role}':"
        puts '-' * 40

        # Use multi_index for O(1) lookup instead of O(n) scanning
        customers = Onetime::Customer.find_all_by_role(target_role)

        customers.each do |customer|
          obscured = OT::Utils.obscure_email(customer.email)
          verified = customer.verified? ? 'verified' : 'unverified'
          puts format('  %s (%s)', obscured, verified)
        end

        puts '-' * 40
        puts "Total: #{customers.size}"
      end

      def validate_email_provided!(email, action)
        return if email && !email.empty?

        puts "Error: Email address required for '#{action}' action"
        puts "Usage: bin/ots role #{action} user@example.com"
        exit 1
      end

      def validate_role!(role)
        return if VALID_ROLES.include?(role)

        puts "Error: Invalid role '#{role}'"
        puts "Valid roles: #{VALID_ROLES.join(', ')}"
        exit 1
      end

      def find_customer!(email)
        unless Onetime::Customer.email_exists?(email)
          obscured = OT::Utils.obscure_email(email)
          puts "Error: Customer not found: #{obscured}"
          exit 1
        end

        Onetime::Customer.find_by_email(email)
      end
    end

    register 'role', RoleCommand
  end
end
