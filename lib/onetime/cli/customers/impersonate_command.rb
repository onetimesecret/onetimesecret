# lib/onetime/cli/customers/impersonate_command.rb
#
# frozen_string_literal: true

# Issue a single-use, short-TTL impersonation grant for a customer — a
# break-glass support capability.
#
# Usage:
#   bin/ots customers impersonate user@example.com \
#     --operator ur_operator --reason "ticket #123 investigating billing"
#   bin/ots customers impersonate ur1234 --operator admin@x.com --reason "..." --yes
#   bin/ots customers impersonate 123 --operator admin@x.com --reason "..." --ttl 300 --json
#
# The mutation (grant mint + admin audit event) is performed by the shared
# Auth::Operations::Customers::Impersonate op (the single implementation). This
# command owns only CLI concerns: identifier parsing, the mandatory
# operator/reason inputs, the confirmation prompt, and output.
#
# The CLI runs outside the auth app's autoloader, so require the op explicitly.
#
# ## Actor identity (ADR-023)
#
# The CLI carries no authenticated colonel session, so the generic customer
# commands attribute mutations to the 'cli' sentinel (Customers::Shared::CLI_ACTOR).
# That is too weak for impersonation: the trail must name the REAL operator. This
# command therefore REQUIRES --operator and passes it as the audit actor; the op
# refuses an empty actor. This is operator-asserted identity (a root shell can
# type any name), the same trust model as any privileged CLI — but it is
# recorded, un-fabricated, and un-bypassable by the wrapper.
require 'json'
require 'auth/operations/customers/impersonate'

# Customers::Shared must exist before `include Customers::Shared` below.
require_relative 'shared'

module Onetime
  module CLI
    class CustomersImpersonateCommand < Command
      include Customers::Shared

      desc 'Issue a single-use, short-TTL impersonation grant for a customer'

      argument :identifier,
        type: :string,
        required: true,
        desc: 'Email, extid, or Rodauth account ID of the customer to impersonate'

      option :operator,
        type: :string,
        default: nil,
        desc: 'PUBLIC id (extid or email) of the REAL operator — required, recorded as audit actor'
      option :reason,
        type: :string,
        default: nil,
        desc: 'Operator-supplied justification — required, recorded in the audit event'
      option :ttl,
        type: :string,
        default: nil,
        desc: "Grant lifetime in seconds (default #{Onetime::ImpersonationGrant::DEFAULT_TTL}, " \
              "clamped #{Onetime::ImpersonationGrant::MIN_TTL}-#{Onetime::ImpersonationGrant::MAX_TTL})"
      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'Skip confirmation prompt'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(identifier:, operator: nil, reason: nil, ttl: nil, yes: false, json: false, **)
        boot_application!

        operator = operator.to_s.strip
        reason   = reason.to_s.strip
        error_exit('--operator is required (the real operator, ADR-023)', json: json) if operator.empty?
        error_exit('--reason is required', json: json) if reason.empty?

        customer = resolve_target(identifier, json: json)
        obscured = customer.obscure_email

        unless yes
          error_exit('Refusing to impersonate without --yes in --json mode', json: true) if json

          print "Issue impersonation grant for #{obscured} as operator '#{operator}' (reason: #{reason})? [y/N] "
          response = $stdin.gets&.strip&.downcase
          unless response == 'y'
            puts 'Aborted.'
            return
          end
        end

        result = Auth::Operations::Customers::Impersonate.new(
          customer: customer,
          actor: operator,
          reason: reason,
          ttl: parse_ttl(ttl),
        ).call

        # The audit event is the durable record; keep the bearer token OUT of logs.
        OT.info "[cli-customers-impersonate] #{obscured} by #{operator} " \
                "status=#{result.status} grant_id=#{result.grant_id} ttl=#{result.expires_in}"

        if json
          output_json(result)
        else
          output_text(result, obscured)
        end
      rescue Auth::Operations::Customers::Impersonate::PrivilegedTarget,
             Auth::Operations::Customers::Impersonate::AnonymousTarget,
             Auth::Operations::Customers::Impersonate::MissingActor,
             Auth::Operations::Customers::Impersonate::MissingReason => ex
        error_exit(ex.message, json: json)
      end

      private

      # nil (option absent) => op uses its default; otherwise integer seconds
      # (the op/model clamps out-of-range values).
      def parse_ttl(ttl)
        return nil if ttl.nil?

        stripped = ttl.to_s.strip
        stripped.empty? ? nil : stripped.to_i
      end

      def output_text(result, obscured)
        puts "Impersonation grant issued for #{obscured}"
        puts "  operator (actor): #{result.actor}"
        puts "  reason:           #{result.reason}"
        puts "  grant id:         #{result.grant_id}"
        puts "  expires in:       #{result.expires_in}s"
        puts
        puts '  Redemption token (single-use BEARER credential — do NOT share, paste, or log):'
        puts "    #{result.token}"
        puts
        puts '  NOTE: the web-surface redemption endpoint is not yet implemented, so'
        puts '        this token is not yet consumable. The grant is auditable and'
        puts '        self-expiring regardless. See impersonate.rb for what redemption needs.'
      end

      def output_json(result)
        puts JSON.pretty_generate(
          status: result.status,
          extid: result.customer.extid,
          email: result.customer.obscure_email,
          actor: result.actor,
          reason: result.reason,
          grant_id: result.grant_id,
          expires_in: result.expires_in,
          token: result.token,
        )
      end

      # Resolve to a mutable, non-anonymous Customer or exit non-zero.
      def resolve_target(identifier, json:)
        error_exit('Identifier is required', json: json) if identifier.to_s.strip.empty?

        customer = resolve_customer(identifier)
        error_exit("Customer not found: #{identifier}", json: json) unless customer
        error_exit('Cannot impersonate anonymous customer', json: json) if customer.anonymous?

        customer
      end

      def error_exit(message, json:)
        if json
          puts JSON.generate({ error: message })
        else
          puts "Error: #{message}"
        end
        exit 1
      end
    end

    register 'customers impersonate', CustomersImpersonateCommand
  end
end
