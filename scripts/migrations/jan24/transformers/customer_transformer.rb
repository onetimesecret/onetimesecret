# frozen_string_literal: true

require_relative 'base_transformer'

module Transformers
  # Transforms customer:* keys from v1 to v2 format.
  # Also generates corresponding Organization and Membership records.
  class CustomerTransformer < BaseTransformer
    def default_stats
      { scanned: 0, transformed: 0, skipped: 0 }
    end

    def route(record, key)
      case key
      when /^customer:([^:]+):object$/
        transform_customer(record, Regexp.last_match(1))
      when /^customer:([^:]+):metadata$/, /^customer:values$/
        # Skip v1 indexes (metadata sorted sets, global values set)
        skip_index_key
      else
        skip_other_key
      end
    end

    private

    def transform_customer(record, email)
      @stats[:scanned] += 1

      # Parse created timestamp from record (extracted during dump phase)
      created_time = parse_created_time(record['created'])

      # Generate new objid for this customer using historical timestamp
      objid = generate_objid(created_time)
      extid = derive_extid_from_uuid(objid, prefix: 'cus')

      # Store mappings for later phases
      email_to_objid[email] = objid

      # Generate corresponding Organization using customer's created timestamp
      org_objid                 = generate_objid(created_time)
      org_extid                 = derive_extid_from_uuid(org_objid, prefix: 'org')
      email_to_org_objid[email] = org_objid

      email_to_org_data[email] = {
        objid: org_objid,
        extid: org_extid,
        owner_id: objid,
        contact_email: email,
        is_default: 'true',
        display_name: "#{email.split('@').first}'s Workspace",
        created: created_time&.to_f&.to_s || Time.now.to_f.to_s,
        v1_source_custid: email,
        migration_status: 'completed',
        migrated_at: Time.now.to_f.to_s,
      }

      # Generate OrganizationMembership using customer's created timestamp
      membership_objid           = generate_objid(created_time)
      membership_extid           = derive_extid_from_uuid(membership_objid, prefix: 'mem')
      email_to_membership[email] = {
        objid: membership_objid,
        extid: membership_extid,
        organization_objid: org_objid,
        customer_objid: objid,
        role: 'owner',
        status: 'active',
        created: created_time&.to_f&.to_s || Time.now.to_f.to_s,
        joined_at: created_time&.to_f || Time.now.to_f,
        token: SecureRandom.urlsafe_base64(32),  # 256-bit entropy
        migration_status: 'completed',
        migrated_at: Time.now.to_f.to_s,
      }

      @stats[:transformed]                         += 1
      @context[:stats][:organizations][:generated] += 1
      @context[:stats][:memberships][:generated]   += 1

      # Transform the key to use objid instead of email
      {
        key: "customer:#{objid}:object",
        original_key: record['key'],
        type: record['type'],
        ttl_ms: record['ttl_ms'],
        dump: record['dump'],
        migration: {
          v1_custid: email,
          v2_objid: objid,
          v2_extid: extid,
          org_objid: org_objid,
          created_time: created_time&.iso8601,
        },
      }
    end
  end
end
