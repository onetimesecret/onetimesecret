# migrations/2026-01-28/lib/transforms/customdomain/index_generator.rb
#
# frozen_string_literal: true

module Migration
  module Transforms
    module Customdomain
      # Generates index commands for CustomDomain records.
      #
      # Creates the following indexes:
      #   - custom_domain:instances (ZADD score=created member=objid)
      #   - custom_domain:display_domain_index (HSET fqdn -> "objid")
      #   - custom_domain:display_domains (HSET fqdn -> "objid") [compat]
      #   - custom_domain:extid_lookup (HSET extid -> "objid")
      #   - custom_domain:objid_lookup (HSET objid -> "objid")
      #   - custom_domain:owners (HSET objid -> "org_id")
      #   - organization:{org_id}:domains (ZADD score=created member=objid)
      #
      # Usage in Kiba job:
      #   transform Customdomain::IndexGenerator, stats: stats
      #
      class IndexGenerator < IndexGeneratorBase
        def generate_indexes(record)
          commands = []
          objid = record[:objid]
          extid = record[:extid]
          org_id = record[:org_id]
          v2_fields = record[:v2_fields] || {}
          created = extract_created(record)

          # Instance index: custom_domain:instances (sorted set)
          commands << zadd('custom_domain:instances', created, objid)
          increment_stat(:domain_instance_entries)

          # Display domain lookups
          display_domain = v2_fields['display_domain'] || record[:display_domain]
          if display_domain && !display_domain.empty?
            commands << hset('custom_domain:display_domain_index', display_domain, objid)
            # Compatibility alias
            commands << hset('custom_domain:display_domains', display_domain, objid)
            increment_stat(:domain_display_lookups)
          end

          # ExtID lookup: custom_domain:extid_lookup
          if extid && !extid.empty?
            commands << hset('custom_domain:extid_lookup', extid, objid)
            increment_stat(:domain_extid_lookups)
          end

          # ObjID lookup: custom_domain:objid_lookup
          commands << hset('custom_domain:objid_lookup', objid, objid)
          increment_stat(:domain_objid_lookups)

          # Owner mapping: custom_domain:owners (objid -> org_id)
          if org_id && !org_id.empty?
            commands << hset('custom_domain:owners', objid, org_id)
            increment_stat(:domain_owner_mappings)

            # Organization participation: organization:{org_id}:domains
            commands << zadd("organization:#{org_id}:domains", created, objid)
            increment_stat(:org_domain_participations)
          end

          commands
        end
      end
    end
  end
end
