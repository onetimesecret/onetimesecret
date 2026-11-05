# lib/onetime/cli/org/show_command.rb
#
# frozen_string_literal: true

# Show one organization: identifiers, owner, billing, counts, members, domains.
#
# Usage:
#   bin/ots organizations show on8q30gih2uxu2cw77jzh7caq07   # by extid
#   bin/ots organizations show 0199...-...                   # by objid
#   bin/ots organizations show cus_ABC123                    # by Stripe customer
#   bin/ots organizations show sub_ABC123                    # by Stripe subscription
#   bin/ots organizations show secrets.example.com           # by custom domain
#   bin/ots organizations show ORG --json
#
# ORG follows Org::Shared#resolve_org. Members render by PUBLIC id (customer
# extid) with their membership role and status; emails are obscured.

require 'json'
# Org::Shared must exist before `include Org::Shared` below. Required here (not
# only from the lib/onetime/cli.rb manifest) so this file cannot be loaded in a
# broken order.
require_relative 'shared'

module Onetime
  module CLI
    class OrgShowCommand < Command
      # resolve_org + error_exit (json-aware) + member_rows / format_member_row.
      include Org::Shared

      desc 'Show organization details, billing, members and domains'

      argument :org,
        type: :string,
        required: true,
        desc: 'Org extid, objid, Stripe customer (cus_...) or subscription (sub_...) id, or custom-domain hostname'

      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(org:, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)
        members      = member_rows(organization)
        domains      = organization.list_domains

        if json
          output_json(organization, members, domains)
        else
          output_text(organization, members, domains)
        end
      end

      private

      def output_text(org, members, domains)
        puts '=' * 60
        puts "Organization: #{org.display_name}"
        puts '=' * 60
        puts
        detail_line('extid', org.extid)
        detail_line('objid', org.objid)
        detail_line('owner', owner_label(org))
        detail_line('contact_email', obscured(org.contact_email) || '(none)')
        detail_line('is_default', truthy?(org.is_default))
        detail_line('archived', org.archived?)
        puts
        puts 'Billing:'
        billing(org).each { |key, value| detail_line(key, value || '(none)') }
        puts
        puts 'Counts:'
        counts(org).each { |key, value| detail_line(key, value) }
        puts

        print_members(org, members)
        print_domains(domains)
      end

      def print_members(org, members)
        puts 'Members:'
        if members.empty?
          puts '  (none)'
        else
          puts format_member_row({ extid: 'EXTID', role: 'ROLE', status: 'STATUS', email: 'EMAIL' })
          members.each { |row| puts format_member_row(row) }
        end

        # list_members drops members-set entries with no customer record; say
        # so rather than letting the table and the count silently disagree.
        unbacked = org.member_count - members.size
        if unbacked.positive?
          puts "  (+#{unbacked} member entr#{unbacked == 1 ? 'y' : 'ies'} with no customer record; " \
               "run bin/ots organizations doctor #{org.extid})"
        end
        puts
      end

      def print_domains(domains)
        return if domains.empty?

        puts 'Domains:'
        domains.each do |domain|
          puts "  - #{domain.display_domain}  (state: #{domain.verification_state})"
        end
        puts
      end

      def output_json(org, members, domains)
        owner   = org.owner
        payload = {
          extid: org.extid,
          objid: org.objid,
          display_name: org.display_name,
          owner: owner ? { extid: owner.extid, email: owner.obscure_email } : nil,
          contact_email: obscured(org.contact_email),
          is_default: truthy?(org.is_default),
          archived: org.archived?,
          billing: billing(org),
          counts: counts(org),
          members: members,
          domains: domains.map do |domain|
            { extid: domain.extid, display_domain: domain.display_domain, verification_state: domain.verification_state.to_s }
          end,
        }
        puts JSON.pretty_generate(payload)
      end

      def detail_line(label, value)
        puts format('  %-22s %s', "#{label}:", value)
      end

      def billing(org)
        {
          planid: presence(org.planid),
          stripe_customer_id: presence(org.stripe_customer_id),
          stripe_subscription_id: presence(org.stripe_subscription_id),
          subscription_status: presence(org.subscription_status),
        }
      end

      def counts(org)
        {
          members: org.member_count,
          domains: org.domain_count,
          pending_invitations: org.pending_invitation_count,
        }
      end

      # Owner by PUBLIC id. owner_id is an objid; when it no longer loads the
      # objid is the only handle left, so it is shown as-is (doctor check 1).
      def owner_label(org)
        return '(none)' if org.owner_id.to_s.empty?

        owner = org.owner
        return "(missing customer #{org.owner_id})" unless owner

        "#{owner.extid} (#{owner.obscure_email})"
      end

      def obscured(email)
        return nil if email.to_s.empty?

        OT::Utils.obscure_email(email.to_s)
      end

      # Boolean fields can read back as true or as the string 'true'
      # depending on how the record was written; compare the string form.
      def truthy?(value)
        value.to_s == 'true'
      end

      def presence(value)
        value.to_s.empty? ? nil : value
      end
    end

    register 'organizations show', OrgShowCommand
  end
end
