# lib/onetime/cli/customers/diagnose_command.rb
#
# frozen_string_literal: true

# Diagnose why an account cannot log in or sign up.
#
# Aggregates every relevant signal for one identifier — customer record,
# Rodauth account status, lockout/login failures, verification and reset keys,
# MFA, active sessions, authentication audit log, and the login rate limiter —
# and prints a triage summary (findings) followed by the evidence (sections).
#
# Usage:
#   bin/ots customers diagnose user@example.com
#   bin/ots customers diagnose ur1234567890abcdef
#   bin/ots customers diagnose user@example.com --json
#   bin/ots customers diagnose user@example.com --audit-limit 50

require 'json'

# Thin adapter over the shared Diagnose op (single implementation, epic #20);
# this command owns CLI concerns only (identifier parsing, output formatting).
# The CLI runs outside the auth autoloader, so require it explicitly.
require 'auth/operations/customers/diagnose'

require_relative 'shared'

module Onetime
  module CLI
    class CustomersDiagnoseCommand < Command
      include Customers::Shared

      desc 'Diagnose why an account cannot log in or sign up'

      argument :identifier,
        type: :string,
        required: true,
        desc: 'Email, extid, or Rodauth account ID of the customer'

      option :full,
        type: :boolean,
        default: false,
        desc: 'Show unobscured email addresses'

      option :audit_limit,
        type: :integer,
        default: Auth::Operations::Customers::Diagnose::DEFAULT_AUDIT_LOG_LIMIT,
        desc: 'Authentication audit log entries to include'

      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      SEVERITY_TAGS = {
        critical: '[CRITICAL]',
        warning: '[WARNING] ',
        info: '[info]    ',
      }.freeze

      TIMESTAMP_KEYS = [
        :created, :created_at, :last_login, :last_login_at, :last_use, :suspended_at, :requested_at,
        :email_last_sent, :deadline, :password_changed_at, :at
      ].freeze

      EMAIL_KEYS = [:email].freeze

      def call(identifier:, full: false, audit_limit: nil, json: false, **)
        boot_application!

        if identifier.to_s.strip.empty?
          error_exit('Identifier is required', json: json)
          return
        end

        # resolve_customer adds the CLI-specific numeric Rodauth-account-id
        # lookup; the identifier is still passed through so the op's
        # email-only authdb fallback works when no Customer resolves.
        result = Auth::Operations::Customers::Diagnose.new(
          identifier: identifier,
          customer: resolve_customer(identifier),
          audit_log_limit: audit_limit || Auth::Operations::Customers::Diagnose::DEFAULT_AUDIT_LOG_LIMIT,
        ).call

        if json
          puts JSON.pretty_generate(serializable(result, full: full))
        else
          output_text(result, full: full)
        end

        # Non-zero exit when the identifier resolves to nothing at all, so
        # scripted region sweeps can branch on it.
        exit 1 unless result.found?
      end

      private

      def serializable(result, full:)
        sections = result.sections
        unless full
          sections = deep_obscure_emails(sections)
        end
        { found: result.found?, findings: result.findings, sections: sections }
      end

      def output_text(result, full:)
        puts 'Account Diagnosis'
        puts '=' * 60

        puts
        puts 'Findings'
        puts '-' * 60
        if result.findings.empty?
          puts '  No blocking condition found. Auth state looks healthy;'
          puts '  suspect client-side issues (cookies, CSP, custom-domain'
          puts '  signin config) or the wrong region.'
        else
          result.findings.each do |finding|
            tag = SEVERITY_TAGS.fetch(finding[:severity], '[?]       ')
            puts "  #{tag} #{finding[:code]}"
            puts "             #{finding[:message]}"
          end
        end

        result.sections.each do |name, data|
          puts
          puts name.to_s.tr('_', ' ').capitalize
          puts '-' * 60
          print_section(data, full: full)
        end
      end

      def print_section(data, full:, indent: 2)
        pad = ' ' * indent
        if data[:available] == false
          puts "#{pad}(unavailable: #{data[:reason] || 'unknown'})"
          return
        end

        data.each do |key, value|
          next if key == :available

          case value
          when Array
            puts "#{pad}#{key}:#{' (none)' if value.empty?}"
            value.each { |item| puts "#{pad}  - #{format_value(item, key: key, full: full)}" }
          when Hash
            puts "#{pad}#{key}: #{format_value(value, key: key, full: full)}"
          else
            puts format('%s%-22s %s', pad, "#{key}:", format_value(value, key: key, full: full))
          end
        end
      end

      def format_value(value, key:, full:)
        return '(none)' if value.nil?

        if key?(TIMESTAMP_KEYS, key) && value.is_a?(Numeric)
          return format_timestamp(value)
        end
        if key?(EMAIL_KEYS, key) && !full
          return OT::Utils.obscure_email(value.to_s)
        end
        if value.is_a?(Hash)
          return value.map { |k, v| "#{k}=#{format_value(v, key: k, full: full)}" }.join(' ')
        end

        value.to_s
      end

      def format_timestamp(ts)
        return '(unknown)' if ts.nil? || ts.to_f <= 0

        Time.at(ts.to_f).utc.strftime('%Y-%m-%d %H:%M:%S UTC')
      end

      # The op's own keys are symbols, but values decoded from a json column
      # (audit-log metadata) carry STRING keys. A symbol-only `include?` silently
      # skips those, so a nested address printed unobscured — defence in depth
      # rather than a live leak, since the two metadata writers that record an
      # email already obscure it (see config/features/audit_logging.rb), but the
      # next writer should not have to know that. Compare on a normalized key,
      # exactly as deep_obscure_emails does.
      def key?(keys, key)
        keys.include?(key.to_s.to_sym)
      end

      # Obscure every email-valued field in the nested section hash for JSON
      # output without --full (mirrors show_command's obscure-by-default).
      def deep_obscure_emails(node)
        case node
        when Hash
          node.to_h do |key, value|
            if EMAIL_KEYS.include?(key.to_sym) && value.is_a?(String) && value.include?('@')
              [key, OT::Utils.obscure_email(value)]
            else
              [key, deep_obscure_emails(value)]
            end
          end
        when Array
          node.map { |item| deep_obscure_emails(item) }
        else
          node
        end
      end

      def error_exit(message, json: false)
        if json
          puts JSON.generate({ error: message })
        else
          puts "Error: #{message}"
        end
        exit 1
      end
    end

    register 'customers diagnose', CustomersDiagnoseCommand
  end
end
