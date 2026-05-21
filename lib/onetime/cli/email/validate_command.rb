# lib/onetime/cli/email/validate_command.rb
#
# frozen_string_literal: true

# CLI command for validating email addresses using Truemail.
#
# Usage:
#   bin/ots email validate user@example.com          # MX validation (default)
#   bin/ots email validate user@example.com --regex  # Format-only validation
#   bin/ots email validate user@example.com --smtp   # Full SMTP validation
#   bin/ots email validate user@example.com --json   # JSON output
#
# Useful for debugging email delivery issues and testing allowlist/denylist.

require 'json'

module Onetime
  module CLI
    module Email
      class ValidateCommand < Command
        desc 'Validate an email address using Truemail'

        argument :email, type: :string, required: true, desc: 'Email address to validate'

        option :mx,
          type: :boolean,
          default: false,
          desc: 'Use MX record validation (default when no mode specified)'

        option :regex,
          type: :boolean,
          default: false,
          desc: 'Use format-only (regex) validation'

        option :smtp,
          type: :boolean,
          default: false,
          desc: 'Use full SMTP validation'

        option :json,
          type: :boolean,
          default: false,
          aliases: ['j'],
          desc: 'Output as JSON'

        # Validation modes in priority order
        MODES = [:smtp, :mx, :regex].freeze

        def call(email:, mx: false, regex: false, smtp: false, json: false, **)
          boot_application!

          unless Onetime::Runtime.email.configured?
            warn 'Error: Truemail not configured.'
            warn 'Add mail.truemail section to config with verifier_email.'
            exit 1
          end

          mode = determine_mode(smtp, mx, regex)

          begin
            result = Truemail.validate(email, with: mode)
          rescue StandardError => ex
            warn "Error: Validation failed - #{ex.message}"
            exit 1
          end

          if json
            output_json(result, mode)
          else
            output_text(result, mode)
          end

          exit(result.result.valid? ? 0 : 1)
        end

        private

        def determine_mode(smtp, mx, regex)
          return :smtp if smtp
          return :regex if regex
          return :mx if mx

          # Default to MX when no flag specified
          :mx
        end

        def output_json(validator, mode)
          r                   = validator.result
          output              = {
            email: r.email,
            valid: r.valid?,
            mode: mode.to_s,
            domain: r.domain,
            mail_servers: r.mail_servers,
            errors: r.errors,
            configuration: extract_list_config,
          }
          output[:smtp_debug] = format_smtp_debug(r.smtp_debug) if r.smtp_debug
          puts JSON.pretty_generate(output)
        end

        def output_text(validator, mode)
          r      = validator.result
          status = r.valid? ? 'VALID' : 'INVALID'

          puts format('Email:     %s', r.email)
          puts format('Status:    %s', status)
          puts format('Mode:      %s', mode)
          puts format('Domain:    %s', r.domain) if r.domain && !r.domain.empty?

          if r.mail_servers&.any?
            puts format('MX:        %s', r.mail_servers.join(', '))
          end

          if r.errors&.any?
            puts
            puts 'Errors:'
            r.errors.each do |key, message|
              puts format('  %s: %s', key, message)
            end
          end

          print_list_match(r)
          print_smtp_debug(r.smtp_debug) if r.smtp_debug
          print_config_summary
        end

        def print_list_match(result)
          # Check if email/domain matches configured lists
          config = Truemail.configuration
          email  = result.email.to_s.downcase
          domain = result.domain.to_s.downcase

          matches = []

          if config.whitelisted_emails&.map(&:downcase)&.include?(email)
            matches << 'allowlist (email)'
          end
          if config.blacklisted_emails&.map(&:downcase)&.include?(email)
            matches << 'denylist (email)'
          end
          if config.whitelisted_domains&.map(&:downcase)&.include?(domain)
            matches << 'allowlist (domain)'
          end
          if config.blacklisted_domains&.map(&:downcase)&.include?(domain)
            matches << 'denylist (domain)'
          end

          return if matches.empty?

          puts
          puts format('Lists:     %s', matches.join(', '))
        end

        def print_smtp_debug(debug)
          return unless debug&.any?

          puts
          puts 'SMTP Debug:'
          debug.each do |entry|
            puts format('  %s:%s', entry.host, entry.port)
            puts format('    connection: %s', entry.connection ? 'ok' : 'failed')
            puts format('    response: %s', entry.response_body) if entry.response_body
            puts format('    errors: %s', entry.errors.inspect) if entry.errors&.any?
          end
        end

        def format_smtp_debug(debug)
          return [] unless debug&.any?

          debug.map do |entry|
            {
              host: entry.host,
              port: entry.port,
              connection: entry.connection,
              response_body: entry.response_body,
              errors: entry.errors,
            }
          end
        end

        def print_config_summary
          config    = Truemail.configuration
          has_lists = [
            config.whitelisted_emails,
            config.blacklisted_emails,
            config.whitelisted_domains,
            config.blacklisted_domains,
          ].any? { |l| l&.any? }

          return unless has_lists

          puts
          puts 'Configured lists:'
          print_list('  allowlist emails', config.whitelisted_emails)
          print_list('  denylist emails', config.blacklisted_emails)
          print_list('  allowlist domains', config.whitelisted_domains)
          print_list('  denylist domains', config.blacklisted_domains)
        end

        def print_list(label, items)
          return unless items&.any?

          puts format('%s: %s', label, items.join(', '))
        end

        def extract_list_config
          config = Truemail.configuration
          {
            whitelisted_emails: config.whitelisted_emails || [],
            blacklisted_emails: config.blacklisted_emails || [],
            whitelisted_domains: config.whitelisted_domains || [],
            blacklisted_domains: config.blacklisted_domains || [],
          }
        end
      end
    end

    register 'email validate', Email::ValidateCommand
  end
end
