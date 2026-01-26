# frozen_string_literal: true

require_relative 'base'

module IndexRebuilder
  # Builds OrgMembership model indexes:
  # - org_membership:instances (zset: objid -> joined_at)
  # - org_membership:token_lookup (hash: token -> objid)
  # - org_membership:org_email_lookup (hash: org_objid:email -> objid)
  # - org_membership:org_customer_lookup (hash: org_objid:customer_objid -> objid)
  class MembershipIndexes < Base
    def build_all
      build_instances
      build_lookup_indexes
    end

    def build_instances
      build_instances_set('org_membership', 'org_membership')
    end

    def build_lookup_indexes
      puts '  Building org_membership indexes...'

      token_lookup        = 'org_membership:token_lookup'
      org_email_lookup    = 'org_membership:org_email_lookup'
      org_customer_lookup = 'org_membership:org_customer_lookup'
      count               = 0

      scan_keys('org_membership:*:object') do |key|
        membership = valkey.hgetall(key)
        objid      = membership['objid']
        next if objid.to_s.empty?

        unless dry_run
          # Token lookup
          unless membership['token'].to_s.empty?
            valkey.hset(token_lookup, membership['token'], objid)
          end

          # Org+email lookup (for pending invites)
          org_objid     = membership['organization_objid']
          invited_email = membership['invited_email']
          if org_objid && invited_email
            composite_key = "#{org_objid}:#{invited_email.downcase}"
            valkey.hset(org_email_lookup, composite_key, objid)
          end

          # Org+customer lookup (for active memberships)
          customer_objid = membership['customer_objid']
          if org_objid && customer_objid
            composite_key = "#{org_objid}:#{customer_objid}"
            valkey.hset(org_customer_lookup, composite_key, objid)
          end
        end
        count += 1
      end

      puts "    Built membership indexes (#{count} memberships)"
      stats[:unique_indexes][:created] += count
    end
  end
end
