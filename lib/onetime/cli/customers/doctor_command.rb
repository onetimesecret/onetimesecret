# lib/onetime/cli/customers/doctor_command.rb
#
# frozen_string_literal: true

# Check and repair customer data integrity issues.
#
# Performs the following integrity checks:
#   1. default_org_id points to existing org that customer is member of (CRITICAL)
#   2. email_index entries match customer email (HIGH)
#   3. email_index has entry for customer (HIGH)
#   4. customer.organizations bidirectional sync with org.members (MEDIUM)
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

      SEVERITY_ORDER = { critical: 0, high: 1, medium: 2, warning: 3, low: 4 }.freeze

      # Valid customer roles
      VALID_ROLES = %w[customer anonymous colonel].freeze

      # Valid verified_by values
      VALID_VERIFIED_BY = %w[email stripe_payment autoverify].freeze

      # Counter fields to check
      COUNTER_FIELDS = [:secrets_created, :secrets_burned, :secrets_shared, :emails_sent].freeze

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
            4. organization membership bidirectional sync (MEDIUM)
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

      def check_customer(customer, report, repair:)
        report[:checked] += 1
        issues            = []

        # CHECK: default_org_id validity
        check_orphan_default_org(customer, issues, report, repair: repair)

        # CHECK: email_index entry exists and is correct
        check_email_index_entry(customer, issues, report, repair: repair)

        # CHECK: organization membership bidirectional sync
        check_org_membership_sync(customer, issues, report, repair: repair)

        # CHECK: role validity
        check_role_validity(customer, issues)

        # CHECK: verified/verified_by consistency
        check_verified_consistency(customer, issues, report, repair: repair)

        # CHECK: counter sanity
        check_counter_sanity(customer, issues, report, repair: repair)

        # CHECK: field serialization (JSON contract)
        check_field_serialization(customer, issues, report, repair: repair)

        if issues.empty?
          report[:healthy] += 1
        else
          report[:issues] << {
            customer_extid: customer.extid,
            customer_objid: customer.objid,
            email: customer.obscure_email,
            issues: issues.sort_by { |i| SEVERITY_ORDER[i[:severity]] },
          }
        end
      end

      # Index-level check for orphan email_index entries
      def check_email_index_integrity(report, repair:)
        issues          = []
        stale_count     = 0
        mismatch_count  = 0

        Onetime::Customer.email_index.hgetall.each do |email, objid|
          customer = Onetime::Customer.load(objid)

          if customer.nil?
            stale_count += 1
            if repair
              Onetime::Customer.email_index.remove_field(email)
              OT.info "[customers doctor] Removed orphan email_index[#{email}] -> #{objid}"
            end
          elsif customer.email.to_s.downcase != email.downcase
            issues << {
              check: :email_index_mismatch,
              severity: :high,
              message: "email_index[#{email}] -> customer with email #{customer.email}",
              email: email,
              customer_objid: objid,
              actual_email: customer.email,
              repairable: true,
            }

            if repair
              # Set correct entry before removing wrong one so there's no window with a missing key
              Onetime::Customer.email_index[customer.email] = objid
              Onetime::Customer.email_index.remove_field(email)
              OT.info "[customers doctor] Fixed email_index: #{email} -> #{customer.email} -> #{objid}"
              mismatch_count                               += 1
            end
          end
        end

        if stale_count.positive?
          if repair
            report[:repaired] << {
              action: :email_index_orphans_cleaned,
              count: stale_count,
            }
          else
            issues << {
              check: :email_index_stale,
              severity: :high,
              message: "#{stale_count} email_index entries point to deleted customers",
              count: stale_count,
              repairable: true,
            }
          end
        end

        if mismatch_count.positive?
          report[:repaired] << {
            action: :email_index_mismatches_fixed,
            count: mismatch_count,
          }
        end

        return if issues.empty?

        report[:issues] << {
          type: :indexes,
          issues: issues.sort_by { |i| SEVERITY_ORDER[i[:severity]] },
        }
      end

      # CHECK: default_org_id points to existing org that customer is member of
      def check_orphan_default_org(customer, issues, report, repair:)
        return if customer.default_org_id.to_s.empty?

        organization = Onetime::Organization.load(customer.default_org_id)

        if organization.nil?
          issues << {
            check: :orphan_default_org,
            severity: :critical,
            message: "default_org_id '#{customer.default_org_id}' points to deleted organization",
            repairable: true,
            repair_action: 'Clear default_org_id field',
          }

          if repair
            customer.default_org_id = nil
            customer.save
            OT.info "[customers doctor] Cleared default_org_id for #{customer.extid}"
            report[:repaired] << {
              customer: customer.extid,
              action: :default_org_cleared,
              reason: :org_deleted,
            }
          end
          return
        end

        # Org exists but customer may not be a member
        return if organization.member?(customer)

        issues << {
          check: :orphan_default_org,
          severity: :critical,
          message: "default_org_id '#{customer.default_org_id}' points to org customer is not a member of",
          repairable: true,
          repair_action: 'Clear default_org_id field',
        }

        return unless repair

        customer.default_org_id = nil
        customer.save
        OT.info "[customers doctor] Cleared default_org_id for #{customer.extid} (not a member)"
        report[:repaired] << {
          customer: customer.extid,
          action: :default_org_cleared,
          reason: :not_member,
        }
      end

      # CHECK: email_index entry exists and matches
      def check_email_index_entry(customer, issues, report, repair:)
        return if customer.email.to_s.empty?

        indexed_objid = Onetime::Customer.email_index[customer.email]

        if indexed_objid.nil?
          issues << {
            check: :email_index_missing,
            severity: :high,
            message: "no email_index entry for #{customer.obscure_email}",
            repairable: true,
            repair_action: 'Add email_index entry',
          }

          if repair
            Onetime::Customer.email_index[customer.email] = customer.objid
            OT.info "[customers doctor] Added email_index[#{customer.email}] -> #{customer.objid}"
            report[:repaired] << {
              customer: customer.extid,
              action: :email_index_added,
            }
          end
        elsif indexed_objid != customer.objid
          issues << {
            check: :email_index_mismatch,
            severity: :high,
            message: "email_index[#{customer.obscure_email}] points to #{indexed_objid}, expected #{customer.objid}",
            repairable: true,
            repair_action: 'Fix email_index entry',
          }

          if repair
            Onetime::Customer.email_index[customer.email] = customer.objid
            OT.info "[customers doctor] Fixed email_index[#{customer.email}] -> #{customer.objid}"
            report[:repaired] << {
              customer: customer.extid,
              action: :email_index_fixed,
            }
          end
        end
      end

      # CHECK: customer.organizations bidirectional sync with org.members
      def check_org_membership_sync(customer, issues, report, repair:)
        # Check organizations customer thinks they belong to
        customer.organizations.to_a.each do |org_objid|
          organization = Onetime::Organization.load(org_objid)

          if organization.nil?
            # Org deleted but customer still has reference
            issues << {
              check: :org_membership_desync,
              severity: :medium,
              message: "customer.organizations contains deleted org #{org_objid}",
              org_objid: org_objid,
              repairable: true,
              repair_action: 'Remove from customer.organizations',
            }

            if repair
              customer.organizations.remove(org_objid)
              OT.info "[customers doctor] Removed deleted org #{org_objid} from #{customer.extid}.organizations"
              report[:repaired] << {
                customer: customer.extid,
                action: :stale_org_removed,
                org_objid: org_objid,
              }
            end
          elsif !organization.member?(customer)
            # Org exists but doesn't have customer in members
            issues << {
              check: :org_membership_desync,
              severity: :medium,
              message: "customer in organizations set for #{organization.extid} but not in org.members",
              org_extid: organization.extid,
              repairable: true,
              repair_action: 'Add customer to org.members',
            }

            if repair
              organization.add_members_instance(customer)
              OT.info "[customers doctor] Added #{customer.extid} to #{organization.extid}.members"
              report[:repaired] << {
                customer: customer.extid,
                action: :added_to_org_members,
                org: organization.extid,
              }
            end
          end
        end
      end

      # CHECK: role has valid value
      def check_role_validity(customer, issues)
        role = customer.role.to_s
        return if role.empty? # No role is OK for some accounts
        return if VALID_ROLES.include?(role)

        issues << {
          check: :role_invalid,
          severity: :medium,
          message: "role '#{role}' is not a recognized value (expected: #{VALID_ROLES.join(', ')})",
          repairable: false,
          repair_action: 'Manual decision required: determine correct role',
        }
      end

      # CHECK: verified/verified_by consistency
      def check_verified_consistency(customer, issues, report, repair:)
        verified    = customer.verified.to_s == 'true'
        verified_by = customer.verified_by.to_s

        return unless verified && verified_by.empty?

        issues << {
          check: :verified_inconsistent,
          severity: :warning,
          message: "verified='true' but verified_by is empty",
          repairable: true,
          repair_action: "Set verified_by to 'legacy'",
        }

        return unless repair

        customer.verified_by = 'legacy'
        customer.save
        OT.info "[customers doctor] Set verified_by='legacy' for #{customer.extid}"
        report[:repaired] << {
          customer: customer.extid,
          action: :verified_by_set,
          value: 'legacy',
        }
      end

      # CHECK: counter fields are non-negative
      def check_counter_sanity(customer, issues, report, repair:)
        negative_counters = []

        COUNTER_FIELDS.each do |field|
          value = customer.send(field).to_i
          negative_counters << { field: field, value: value } if value.negative?
        end

        return if negative_counters.empty?

        issues << {
          check: :counter_negative,
          severity: :low,
          message: "#{negative_counters.size} counter(s) have negative values",
          counters: negative_counters,
          repairable: true,
          repair_action: 'Reset negative counters to 0',
        }

        return unless repair

        negative_counters.each do |counter|
          customer.send(:"#{counter[:field]}=", 0)
        end
        customer.save
        OT.info "[customers doctor] Reset #{negative_counters.size} negative counter(s) for #{customer.extid}"
        report[:repaired] << {
          customer: customer.extid,
          action: :counters_reset,
          fields: negative_counters.map { |c| c[:field] },
        }
      end

      # CHECK: hash field values are properly JSON-serialized
      def check_field_serialization(customer, issues, report, repair:)
        raw_hash = Onetime::Customer.dbclient.hgetall(customer.dbkey)
        bad_fields = []

        raw_hash.each do |field_name, raw_value|
          bad_fields << field_name unless properly_serialized?(raw_value)
        end

        return if bad_fields.empty?

        issues << {
          check: :field_serialization,
          severity: :high,
          message: "#{bad_fields.size} field(s) not JSON-serialized: #{bad_fields.join(', ')}",
          fields: bad_fields,
          repairable: true,
          repair_action: 'Re-serialize fields with JSON.dump',
        }

        return unless repair

        updates = bad_fields.each_with_object({}) do |field_name, hash|
          hash[field_name] = JSON.dump(raw_hash[field_name])
        end
        Onetime::Customer.dbclient.hset(customer.dbkey, updates)
        OT.info "[customers doctor] Re-serialized #{bad_fields.size} field(s) for #{customer.extid}: #{bad_fields.join(', ')}"
        report[:repaired] << {
          customer: customer.extid,
          action: :fields_reserialized,
          fields: bad_fields,
        }
      end

      # Checks whether a raw Redis value is a valid JSON literal.
      # Empty strings are legitimate "cleared" field state, not a serialization issue.
      def properly_serialized?(raw_value)
        return true if raw_value.nil? || raw_value.empty?

        JSON.parse(raw_value)
        true
      rescue JSON::ParserError
        false
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
