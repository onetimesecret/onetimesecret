# lib/onetime/cli/email/test_command.rb
#
# frozen_string_literal: true

# CLI command for sending a test email to verify delivery connectivity.
#
# Usage:
#   ots email test --to user@example.com
#   ots email test --to user@example.com --dry-run
#   ots email test --to user@example.com --format json
#
# Sends by default (no --execute flag needed). Use --dry-run to preview.
# Bypasses templates — sends a plain-text diagnostic email directly.

require 'json'
require 'socket'

module Onetime
  module CLI
    module Email
      class TestCommand < Command
        desc 'Send a test email to verify delivery connectivity'

        option :to,
          type: :string,
          required: true,
          desc: 'Recipient email address'

        option :dry_run,
          type: :boolean,
          default: false,
          desc: 'Show what would be sent without sending'

        option :format,
          type: :string,
          default: 'text',
          aliases: ['f'],
          desc: 'Output format: text or json'

        def call(to:, dry_run: false, format: 'text', **)
          boot_application!

          provider  = Onetime::Mail::Mailer.send(:determine_provider)
          hostname  = Socket.gethostname
          timestamp = Time.now.utc.iso8601

          email = {
            to: to,
            from: Onetime::Mail::Mailer.from_address,
            subject: "[OTS] Email delivery test - #{timestamp}",
            text_body: "This is a test email from Onetime Secret CLI.\n\nProvider: #{provider}\nTimestamp: #{timestamp}\nHost: #{hostname}",
          }

          if format == 'json'
            output_json(email, provider, hostname, dry_run)
          else
            output_text(email, provider, hostname, dry_run)
          end

          deliver!(email) unless dry_run
        rescue StandardError => ex
          warn "Error: #{ex.message}"
          exit 1
        end

        private

        def deliver!(email)
          start   = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          Onetime::Mail::Mailer.delivery_backend.deliver(email)
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

          puts
          puts format('Status:    SENT (%.2fs)', elapsed)
        rescue StandardError => ex
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          $stderr.puts
          warn format('Status:    FAILED (%.2fs)', elapsed)
          warn "Error:     #{ex.message}"
          exit 1
        end

        def output_text(email, provider, hostname, dry_run)
          puts format('Provider:  %s', provider)
          puts format('Host:      %s', hostname)
          puts format('To:        %s', email[:to])
          puts format('From:      %s', email[:from])
          puts format('Subject:   %s', email[:subject])
          puts
          puts "\u2500\u2500 Body \u2500\u2500"
          puts email[:text_body]
          puts
          if dry_run
            puts 'Mode: DRY RUN (omit --dry-run to send)'
          end
        end

        def output_json(email, provider, hostname, dry_run)
          result = {
            provider: provider,
            host: hostname,
            to: email[:to],
            from: email[:from],
            subject: email[:subject],
            text_body: email[:text_body],
            mode: dry_run ? 'dry_run' : 'live',
          }
          puts JSON.pretty_generate(result)
        end
      end
    end

    register 'email test', Email::TestCommand
  end
end
