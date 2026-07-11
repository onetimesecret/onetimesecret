# lib/onetime/cli/customers/doctor_command.rb
#
# frozen_string_literal: true

# Check and repair customer data integrity issues.
#
# Performs the following integrity checks:
#   1. default_org_id points to existing org that customer is member of (CRITICAL)
#   2. email_index entries match customer email (HIGH)
#   3. email_index has entry for customer (HIGH)
#   4. customer participations reverse index sync with org.members (MEDIUM)
#   5. role field has valid value (MEDIUM)
#   6. verified/verified_by consistency (WARNING)
#   7. counter fields are non-negative (LOW)
#   8. hash field values are properly JSON-serialized (HIGH)
#
# Usage:
#   bin/ots customers doctor trytoremember@me.not  # Check by email or extid
#   bin/ots customers doctor --all                 # Scan all customers
#   bin/ots customers doctor --all --repair        # Auto-repair issues
#   bin/ots customers doctor --all --json          # JSON output

require 'json'

# The integrity CHECK + REPAIR logic (per-customer and email_index) is delegated
# to the shared Auth::Operations::Customers::Doctor op (single implementation);
# this command owns orchestration (scan-all, output formatting, exit codes). The
# CLI runs outside the auth autoloader, so require the op + shared helpers.
require 'auth/operations/customers/doctor'
require 'onetime/cli/customers/shared'

module Onetime
  module CLI
    # rubocop:disable Metrics/ClassLength
    class CustomersDoctorCommand < Command
      desc 'Check customer data integrity'

      argument :identifier,
        type: :string,
        required: false,
        desc: 'Customer email or extid'

      option :all,
        type: :boolean,
        default: false,
        desc: 'Scan all customers'

      option :repair,
        type: :boolean,
        default: false,
        desc: 'Auto-repair issues (default: audit only)'

      option :json,
        type: :boolean,
        default: false,
        desc: 'JSON output'

      # Check severities, constants, and the integrity rules now live on the
      # shared op (Auth::Operations::Customers::Doctor). See that op for the
      # SEVERITY_ORDER / VALID_ROLES / COUNTER_FIELDS definitions.

      def call(identifier: nil, all: false, repair: false, json: false, **)
        boot_application!

        unless identifier || all
          show_usage
          return
        end

        report = { checked: 0, healthy: 0, issues: [], repaired: [] }

        if identifier
          customer = load_customer(identifier)
          check_customer(customer, report, repair: repair)
        else
          check_email_index_integrity(report, repair: repair)
          scan_all_customers(report, repair: repair)
        end

        output_report(report, json: json, repair: repair)
        exit_with_status(report, repair: repair)
      end

      private

      def show_usage
        puts <<~USAGE
          Usage: bin/ots customers doctor [IDENTIFIER] [options]

          Check customer data integrity and optionally repair issues.

          Arguments:
            IDENTIFIER              Customer email or extid

          Options:
            --all                   Scan all customers
            --repair                Auto-repair issues (default: audit only)
            --json                  JSON output

          Examples:
            bin/ots customers doctor trytoremember@me.not
            bin/ots customers doctor ur1a2b3c4d5e6f
            bin/ots customers doctor --all
            bin/ots customers doctor --all --repair

          Checks performed:
            1. default_org_id points to valid org membership (CRITICAL)
            2. email_index entries are consistent (HIGH)
            3. customer has email_index entry (HIGH)
            4. participation reverse index sync with org.members (MEDIUM)
            5. role field has valid value (MEDIUM)
            6. verified/verified_by consistency (WARNING)
            7. counter fields are non-negative (LOW)
            8. hash field values are properly JSON-serialized (HIGH)
        USAGE
      end

      def load_customer(identifier)
        # Try email first, then extid
        customer   = Onetime::Customer.find_by_email(identifier)
        customer ||= Onetime::Customer.find_by_extid(identifier)

        unless customer
          puts "Customer not found: #{identifier}"
          exit 1
        end
        customer
      end

      def scan_all_customers(report, repair:)
        Onetime::Customer.instances.each do |objid|
          customer = Onetime::Customer.load(objid)
          next unless customer

          check_customer(customer, report, repair: repair)
        end
      end

      # Per-customer integrity check. Delegates the actual checks + repairs to
      # the shared op and aggregates the result into the CLI's report structure.
      def check_customer(customer, report, repair:)
        report[:checked] += 1

        op_report = Auth::Operations::Customers::Doctor.new(
          customer: customer,
          repair: repair,
          # Only attribute an audit actor when a repair can actually mutate.
          actor: repair ? Customers::Shared::CLI_ACTOR : nil,
        ).call

        report[:repaired].concat(op_report.repaired)

        if op_report.issues.empty?
          report[:healthy] += 1
        else
          report[:issues] << {
            customer_extid: customer.extid,
            customer_objid: customer.objid,
            email: customer.obscure_email,
            issues: op_report.issues,
          }
        end
      end

      # Index-level check for orphan email_index entries. Delegates to the op's
      # class-level check and merges into the report.
      def check_email_index_integrity(report, repair:)
        index_report = Auth::Operations::Customers::Doctor.check_email_index(repair: repair)

        report[:repaired].concat(index_report[:repaired])

        return if index_report[:issues].empty?

        report[:issues] << {
          type: :indexes,
          issues: index_report[:issues],
        }
      end

      # Output helpers

      def output_report(report, json:, repair:)
        if json
          output_json(report)
        else
          output_text(report, repair: repair)
        end
      end

      def output_json(report)
        puts JSON.pretty_generate(report)
      end

      # rubocop:disable Metrics/PerceivedComplexity
      def output_text(report, repair:)
        puts 'Customer Health Check'
        puts '=' * 40
        puts

        puts "Customers checked: #{report[:checked]}"
        puts "Healthy: #{report[:healthy]}"
        puts "With issues: #{report[:issues].count { |i| !i[:type] }}"
        puts

        if report[:repaired].any?
          puts 'Repaired:'
          report[:repaired].each do |r|
            case r[:action]
            when :email_index_orphans_cleaned
              puts "  Cleaned #{r[:count]} orphan email_index entries"
            when :email_index_mismatches_fixed
              puts "  Fixed #{r[:count]} mismatched email_index entries"
            when :email_index_added
              puts "  #{r[:customer]}: added email_index entry"
            when :email_index_fixed
              puts "  #{r[:customer]}: fixed email_index entry"
            when :default_org_cleared
              puts "  #{r[:customer]}: cleared default_org_id (#{r[:reason]})"
            when :stale_org_removed
              puts "  #{r[:customer]}: removed stale org reference"
            when :added_to_org_members
              puts "  #{r[:customer]}: added to #{r[:org]} members"
            when :verified_by_set
              puts "  #{r[:customer]}: set verified_by='#{r[:value]}'"
            when :counters_reset
              puts "  #{r[:customer]}: reset counters #{r[:fields].join(', ')}"
            when :fields_reserialized
              puts "  #{r[:customer]}: re-serialized fields #{r[:fields].join(', ')}"
            else
              puts "  #{r[:action]}"
            end
          end
          puts
        end

        return if report[:issues].empty?

        puts 'Issues Found:'
        puts '-' * 40

        report[:issues].each do |issue_group|
          puts
          if issue_group[:type] == :indexes
            puts 'Index Integrity:'
          else
            puts "#{issue_group[:customer_extid]} (#{issue_group[:email]})"
          end

          issue_group[:issues].each do |issue|
            severity_label = severity_tag(issue[:severity])
            repairable     = issue[:repairable] ? '' : ' [manual fix required]'
            puts "  #{severity_label} #{issue[:message]}#{repairable}"

            puts "             #{issue[:repair_action]}" if issue[:repair_action]
          end
        end

        return if repair

        all_issues     = report[:issues].flat_map { |group| group[:issues] }
        has_repairable = all_issues.any? { |i| i[:repairable] }

        puts
        puts '-' * 40
        if has_repairable
          puts 'To auto-repair repairable issues, run with --repair'
        else
          puts 'All issues require manual intervention.'
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity

      def severity_tag(severity)
        case severity
        when :critical then '[CRITICAL]'
        when :high     then '[HIGH]    '
        when :medium   then '[MEDIUM]  '
        when :warning  then '[WARNING] '
        when :low      then '[LOW]     '
        else                '[UNKNOWN] '
        end
      end

      def exit_with_status(report, repair:)
        return if report[:issues].empty?

        all_issues     = report[:issues].flat_map { |group| group[:issues] }
        has_repairable = all_issues.any? { |i| i[:repairable] }

        if repair
          if report[:repaired].empty?
            if has_repairable
              exit 1
            else
              puts
              puts 'ERROR: --repair specified but no issues are auto-repairable.'
              puts 'Manual intervention required.'
              exit 2
            end
          end
        else
          exit 1
        end
      end
    end
    # rubocop:enable Metrics/ClassLength

    register 'customers doctor', CustomersDoctorCommand
  end
end
