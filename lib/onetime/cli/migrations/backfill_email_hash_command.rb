# lib/onetime/cli/migrations/backfill_email_hash_command.rb
#
# frozen_string_literal: true

# Backfill email_hash for existing Organization records in Redis.
#
# The email_hash is an HMAC-SHA256 hash of the billing_email, used for
# cross-region subscription federation. This command populates the field
# for organizations created before the federation feature was added.
#
# Usage:
#   bin/ots migrations backfill-email-hash           # Dry run (default)
#   bin/ots migrations backfill-email-hash --run     # Execute backfill
#   bin/ots migrations backfill-email-hash --verbose # Show each organization
#
# @see https://github.com/onetimesecret/onetimesecret/issues/2471

require 'onetime/utils/email_hash'

module Onetime
  module CLI
    class BackfillEmailHashCommand < Command
      desc 'Backfill email_hash for existing organizations'

      option :run,
        type: :boolean,
        default: false,
        desc: 'Execute backfill (default is dry-run)'

      option :verbose,
        type: :boolean,
        default: false,
        aliases: ['v'],
        desc: 'Show detailed progress for each organization'

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(run: false, verbose: false, help: false, **)
        return show_usage_help if help

        boot_application!

        puts "\nOrganization Email Hash Backfill"
        puts '=' * 60

        # Verify FEDERATION_HMAC_SECRET is configured
        begin
          Onetime::Utils::EmailHash.compute('test@example.com')
        rescue Onetime::Problem => ex
          puts "\nConfiguration Error: #{ex.message}"
          puts "\nTo configure, set FEDERATION_HMAC_SECRET in your environment"
          puts 'or add site.federation_hmac_secret to your config file.'
          return
        end

        all_org_ids = Onetime::Organization.instances.all
        total_orgs  = all_org_ids.size

        if total_orgs.zero?
          puts "\nNo organizations found in Redis."
          return
        end

        puts "\nDiscovered #{total_orgs} organizations"

        dry_run = !run
        if dry_run
          puts "\nDRY RUN MODE - No changes will be made"
          puts "To execute backfill, run with --run flag\n"
        end

        stats = {
          total: 0,
          updated: 0,
          skipped_no_email: 0,
          skipped_has_hash: 0,
          errors: [],
        }

        all_org_ids.each_with_index do |objid, idx|
          stats[:total] += 1

          begin
            org = Onetime::Organization.load(objid)

            unless org
              stats[:errors] << "#{objid}: Organization not found"
              next
            end

            # Skip if no billing_email
            if org.billing_email.to_s.strip.empty?
              stats[:skipped_no_email] += 1
              if verbose
                puts "  [#{idx + 1}/#{total_orgs}] Skipping (no billing_email): #{org.extid}"
              end
              next
            end

            # Skip if already has email_hash
            unless org.email_hash.to_s.strip.empty?
              stats[:skipped_has_hash] += 1
              if verbose
                puts "  [#{idx + 1}/#{total_orgs}] Skipping (has hash): #{org.extid}"
              end
              next
            end

            # Compute and store hash
            email_hash = org.compute_email_hash!

            if dry_run
              puts "  [#{idx + 1}/#{total_orgs}] Would update: #{org.extid} (#{OT::Utils.obscure_email(org.billing_email)})"
            else
              org.save
              if verbose
                puts "  [#{idx + 1}/#{total_orgs}] Updated: #{org.extid} -> #{email_hash[0..7]}..."
              end
            end

            stats[:updated] += 1

            # Progress indicator for non-verbose mode
            if !verbose && (stats[:total] % 50).zero?
              print "\r  Progress: #{stats[:total]}/#{total_orgs} organizations processed"
            end
          rescue StandardError => ex
            error_msg = "#{org&.extid || objid}: #{ex.message}"
            stats[:errors] << error_msg
            puts "  [#{idx + 1}/#{total_orgs}] Error: #{error_msg}"
            OT.le "[BackfillEmailHash] Error for #{objid}: #{ex.message}"
          end
        end

        # Clear progress line
        print "\r" + (' ' * 80) + "\r" unless verbose

        # Report results
        puts "\n" + ('=' * 60)
        puts "Backfill #{dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts "\nStatistics:"
        puts "  Total organizations:        #{stats[:total]}"
        puts "  Updated:                    #{stats[:updated]}"
        puts "  Skipped (no billing_email): #{stats[:skipped_no_email]}"
        puts "  Skipped (already has hash): #{stats[:skipped_has_hash]}"

        if stats[:errors].any?
          puts "\n  Errors:                     #{stats[:errors].size}"
          if verbose
            puts "\n  Error details:"
            stats[:errors].each { |err| puts "    - #{err}" }
          end
        end

        return unless dry_run && stats[:updated] > 0

        puts <<~MESSAGE

          To execute backfill, run:
            bin/ots migrations backfill-email-hash --run

        MESSAGE
      end

      private

      def show_usage_help
        puts <<~USAGE

          Organization Email Hash Backfill

          Usage:
            bin/ots migrations backfill-email-hash [options]

          Description:
            Backfills email_hash for existing Organization records in Redis.
            The email_hash is an HMAC-SHA256 hash of the billing_email, used for
            cross-region subscription federation.

          Options:
            --run                 Execute backfill (default is dry-run)
            --verbose, -v         Show detailed progress for each organization
            --help, -h            Show this help message

          Examples:
            # Preview backfill (dry run)
            bin/ots migrations backfill-email-hash

            # Execute backfill
            bin/ots migrations backfill-email-hash --run

            # Execute with verbose output
            bin/ots migrations backfill-email-hash --run --verbose

          Notes:
            - Command is idempotent (safe to run multiple times)
            - Skips organizations without billing_email
            - Skips organizations that already have email_hash set
            - Requires FEDERATION_HMAC_SECRET to be configured

        USAGE
        true
      end
    end

    register 'migrations backfill-email-hash', BackfillEmailHashCommand
  end
end
