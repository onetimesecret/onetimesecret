# lib/onetime/cli/email/sync_feedback_command.rb
#
# frozen_string_literal: true

# CLI command to pull a provider's deliverability suppression list and ingest
# it into the local suppression list — the operator/cron relay that wires AWS
# SES and Lettermint feedback into the colonel deliverability console.
#
# Usage:
#   ots email sync-feedback                         # default (configured) provider
#   ots email sync-feedback --provider ses
#   ots email sync-feedback --provider lettermint --limit 500
#   ots email sync-feedback --dry-run               # fetch + count, ingest nothing
#   ots email sync-feedback --format json
#
# Intended to run on a schedule (cron) so the local suppression list — which the
# outbound guard consults before every send — stays in step with what the ESP
# has bounced/complained. Idempotent: re-syncing an unchanged list writes the
# same suppressions and adds nothing to the bounce/complaint feed.

require 'json'
require 'onetime/operations/email/sync_provider_feedback'

module Onetime
  module CLI
    module Email
      class SyncFeedbackCommand < Command
        desc 'Pull ESP suppression feedback (SES/Lettermint) into the suppression list'

        # Audit actor sentinel for CLI-initiated ingestion (matches the send-test
        # / customer / session CLI convention). The op attributes the one
        # per-batch AdminAuditEvent to this on the shell path.
        CLI_ACTOR = Onetime::Operations::Email::SyncProviderFeedback::CLI_ACTOR

        option :provider,
          type: :string,
          desc: 'Feedback provider: ses or lettermint (default: configured provider)'

        option :limit,
          type: :integer,
          desc: 'Max records to pull this run'

        option :dry_run,
          type: :boolean,
          default: false,
          desc: 'Fetch and count without ingesting'

        option :format,
          type: :string,
          default: 'text',
          aliases: ['f'],
          desc: 'Output format: text or json'

        def call(provider: nil, limit: nil, dry_run: false, format: 'text', **)
          boot_application!

          result = Onetime::Operations::Email::SyncProviderFeedback.new(
            provider: provider,
            actor: CLI_ACTOR,
            limit: limit,
            dry_run: dry_run,
          ).call

          format == 'json' ? output_json(result) : output_text(result)
        rescue StandardError => ex
          # ArgumentError covers unsupported provider or missing credentials —
          # an operator config problem; every failure is reported plainly with
          # a non-zero exit.
          warn "Error: #{ex.message}"
          exit 1
        end

        private

        def output_text(result)
          puts format('Provider:  %s', result.provider)
          puts format('Fetched:   %d', result.fetched)
          if result.dry_run
            puts 'Mode:      DRY RUN (omit --dry-run to ingest)'
            return
          end

          puts format('Accepted:  %d', result.accepted)
          puts format('Rejected:  %d', result.rejected)
          return if result.errors.empty?

          puts
          puts 'Errors:'
          result.errors.each { |err| puts "  - #{err}" }
        end

        def output_json(result)
          puts JSON.pretty_generate(
            provider: result.provider,
            fetched: result.fetched,
            accepted: result.accepted,
            rejected: result.rejected,
            errors: result.errors,
            dry_run: result.dry_run,
          )
        end
      end
    end

    register 'email sync-feedback', Email::SyncFeedbackCommand
  end
end
