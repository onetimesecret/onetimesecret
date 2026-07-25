# lib/onetime/cli/domains/create_command.rb
#
# frozen_string_literal: true

# Register a custom domain against an organization.
#
# This is the CLI peer of `POST /api/colonel/domains`. Both adapters call the
# same op (Onetime::Operations::Domains::Create), which owns validation,
# creation, certificate provisioning and the single `domain.create`
# AdminAuditEvent. Every other colonel domain verb (verify / probe / repair /
# transfer / remove) already had a CLI peer; create was the gap.
#
# Usage:
#   bin/ots domains create example.com --org on123abc            # confirm, then create
#   bin/ots domains create example.com --org on123abc --yes
#   bin/ots domains create example.com --org on123abc --yes --json
#   bin/ots domains create example.com --org on123abc --yes --no-cert
#
# ORG accepts the organization extid (preferred — what every admin surface
# routes by) or the internal objid.
#
# Lives under lib/onetime/cli (not apps/api/domains/cli) so the require of the
# op is unambiguous at load time; registration is identical either way.

require 'json'
require 'onetime/operations/domains/create'

module Onetime
  module CLI
    class DomainsCreateCommand < Command
      # Audit actor for CLI-initiated mutations. Matches the other domain
      # commands' sentinel — never an operator objid (the shell has no identity).
      CLI_ACTOR = 'cli'

      desc 'Register a custom domain against an organization'

      argument :domain,
        type: :string,
        required: true,
        desc: 'Domain name to register (e.g. secrets.example.com)'

      option :org,
        type: :string,
        default: nil,
        desc: 'Organization extid (or objid) that will own the domain'
      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'Skip confirmation prompt'
      option :cert,
        type: :boolean,
        default: true,
        desc: 'Request an SSL certificate after creating (--no-cert to skip)'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(domain:, org: nil, yes: false, cert: true, json: false, **)
        boot_application!

        error_exit('--org is required', json: json) if org.to_s.strip.empty?

        organization = resolve_org(org)
        error_exit("Organization not found: #{org}", json: json) unless organization

        operation = Onetime::Operations::Domains::Create.new(
          domain: domain,
          org: organization,
          actor: CLI_ACTOR,
          request_certificate: cert,
        )

        # Validate BEFORE prompting so an obviously bad input fails fast, and so
        # the operator sees the normalised FQDN they are about to register.
        check = operation.validate
        error_exit(check.message, json: json) unless check.status == :ok

        unless yes
          error_exit('Refusing to create without --yes in --json mode', json: true) if json

          puts "Domain:       #{check.display_domain}"
          puts "Organization: #{organization.display_name || organization.extid} (#{organization.extid})"
          puts '  (claims an existing ORPHANED record)' if check.claims_orphan
          puts "Certificate:  #{cert ? 'request after create' : 'skipped (--no-cert)'}"
          puts
          print 'Create this domain? [y/N] '
          response = $stdin.gets&.strip&.downcase
          unless response == 'y'
            puts 'Aborted.'
            return
          end
        end

        result = operation.call
        error_exit(result.message, json: json) unless result.status == :created

        OT.info "[cli-domains-create] domain=#{result.display_domain} org=#{organization.extid} extid=#{result.extid}"

        if json
          puts JSON.pretty_generate(
            status: result.status,
            domain_id: result.domain_id,
            extid: result.extid,
            display_domain: result.display_domain,
            org_id: organization.extid,
            claimed_orphan: result.claims_orphan,
            cert_status: result.cert_status,
          )
        else
          puts "Created #{result.display_domain} (#{result.extid}) for #{organization.extid}"
          puts '  Claimed a previously orphaned record' if result.claims_orphan
          puts "  Certificate request: #{result.cert_status}" if result.cert_status
          puts
          puts "Next: bin/ots domains verify #{result.display_domain}"
        end
      end

      private

      # extid first (the documented input), objid as a fallback — the same
      # precedence CreateCustomDomain uses on the HTTP side.
      def resolve_org(identifier)
        value = identifier.to_s.strip
        Onetime::Organization.find_by_extid(value) || Onetime::Organization.load(value)
      end

      def error_exit(message, json:)
        puts(json ? JSON.generate({ error: message }) : "Error: #{message}")
        exit 1
      end
    end

    # Registered twice (not via `aliases:`) — nested Dry::CLI names are
    # registry paths, so an alias has to be its own registration. Mirrors
    # `domains info` / `domains show`.
    register 'domains create', DomainsCreateCommand
    register 'domains add', DomainsCreateCommand
  end
end
