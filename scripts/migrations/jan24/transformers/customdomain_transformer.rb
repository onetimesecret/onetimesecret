# frozen_string_literal: true

require_relative 'base_transformer'

module Transformers
  # Transforms customdomain:* keys from v1 to v2 format.
  # Handles both :object keys and hashkey sub-keys (brand, logo, icon).
  class CustomdomainTransformer < BaseTransformer
    def default_stats
      { scanned: 0, transformed: 0, hashkeys: 0, skipped: 0 }
    end

    def route(record, key)
      case key
      when /^customdomain:([^:]+):object$/
        transform_custom_domain(record, Regexp.last_match(1))
      when /^customdomain:([^:]+):(brand|logo|icon)$/
        transform_custom_domain_hashkey(record, Regexp.last_match(1), Regexp.last_match(2))
      when /^customdomain:(values|owners|display_domains)$/
        # Skip v1 global indexes
        skip_index_key
      else
        skip_other_key
      end
    end

    private

    def transform_custom_domain(record, old_domain_id)
      @stats[:scanned] += 1

      # Parse created timestamp from record (extracted during dump phase)
      created_time = parse_created_time(record['created'])

      # Generate new UUIDv7 objid for this CustomDomain using historical timestamp
      objid = generate_objid(created_time)
      extid = derive_extid_from_uuid(objid, prefix: 'cd')

      # Transform the key pattern: customdomain:{old_hex}:object -> customdomain:{new_uuid}:object
      new_key = "customdomain:#{objid}:object"

      # Store mapping for hashkey transformation
      domainid_to_objid[old_domain_id] = objid

      @stats[:transformed] += 1

      {
        key: new_key,
        original_key: record['key'],
        type: record['type'],
        ttl_ms: record['ttl_ms'],
        dump: record['dump'],
        migration: {
          v1_domainid: old_domain_id,
          v2_objid: objid,
          v2_extid: extid,
          created_time: created_time&.iso8601,
          # The actual custid->org_id mapping happens at load time
          email_to_org_mapping: email_to_org_objid,
        },
      }
    end

    def transform_custom_domain_hashkey(record, old_domain_id, hashkey_name)
      @stats[:hashkeys] += 1

      # Look up the new objid from our mapping
      new_objid = domainid_to_objid[old_domain_id]

      unless new_objid
        # Object record hasn't been processed yet - this shouldn't happen
        # if files are processed in order, but handle gracefully
        puts "  Warning: No objid mapping for domain #{old_domain_id}, keeping original key"
        return {
          key: record['key'],
          type: record['type'],
          ttl_ms: record['ttl_ms'],
          dump: record['dump'],
        }
      end

      # Transform hashkey path: customdomain:{old_hex}:{hashkey} -> customdomain:{new_uuid}:{hashkey}
      new_key = "customdomain:#{new_objid}:#{hashkey_name}"

      {
        key: new_key,
        original_key: record['key'],
        type: record['type'],
        ttl_ms: record['ttl_ms'],
        dump: record['dump'],
      }
    end
  end
end
