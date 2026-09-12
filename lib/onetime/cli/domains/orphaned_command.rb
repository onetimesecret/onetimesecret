# lib/onetime/cli/domains/orphaned_command.rb
#
# frozen_string_literal: true

# List orphaned custom domains (no owning organization) — the CLI peer of
# `GET /api/colonel/domains/orphaned`. Both adapters call the same op
# (Onetime::Operations::Domains::OrphanedScan), a READ-ONLY diagnostic that
# records NO ColonelAuditEvent (CONTRACT 4 — audit is for mutations).
#
# Usage:
#   bin/ots domains orphaned
#   bin/ots domains orphaned --json
#
# The CLI lists ALL orphaned domains sorted by display_domain (the op's
# `per_page: nil` mode returns the full sorted collection unpaginated); the
# colonel endpoint paginates.
#
# Lives under lib/onetime/cli (not apps/api/domains/cli) so the require of the
# op is unambiguous at load time; registration is identical either way.

require 'json'
require 'onetime/operations/domains/orphaned_scan'
require_relative 'shared'

module Onetime
  module CLI
    class DomainsOrphanedCommand < Command
      include Domains::Shared

      desc 'List domains without organization ownership'

      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON for scripting'

      def call(json: false, **)
        boot_application!

        # per_page: nil => full sorted collection, unpaginated (CLI mode).
        result  = Onetime::Operations::Domains::OrphanedScan.new(per_page: nil).call
        domains = result.domains

        OT.info "[cli-domains-orphaned] count=#{domains.size}"

        json ? output_json(result) : output_text(domains)
      end

      private

      def output_json(result)
        puts JSON.pretty_generate(
          total_count: result.total_count,
          domains: result.domains,
        )
      end

      def output_text(domains)
        puts "#{domains.size} orphaned custom domains found"
        return if domains.empty?

        puts
        puts format('%-40s %-12s %-10s %-20s', 'Domain', 'Status', 'Verified', 'Created')
        puts '-' * 85

        domains.each do |domain|
          status   = domain[:verification_state].to_s.empty? ? 'unknown' : domain[:verification_state]
          verified = domain[:verified] ? 'true' : 'false'

          puts format(
            '%-40s %-12s %-10s %-20s',
            domain[:display_domain],
            status,
            verified,
            format_timestamp(domain[:created]),
          )
        end
      end

      # Local copy of the legacy DomainsHelpers#format_timestamp — the new-style
      # commands deliberately do not include that module (see Domains::Shared).
      def format_timestamp(timestamp)
        return 'N/A' unless timestamp

        Time.at(timestamp.to_i).strftime('%Y-%m-%d %H:%M:%S UTC')
      rescue StandardError
        'invalid'
      end
    end

    register 'domains orphaned', DomainsOrphanedCommand
  end
end
