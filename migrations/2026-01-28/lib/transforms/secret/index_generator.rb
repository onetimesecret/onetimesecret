# migrations/2026-01-28/lib/transforms/secret/index_generator.rb
#
# frozen_string_literal: true

module Migration
  module Transforms
    module Secret
      # Generates index commands for Secret records.
      #
      # Creates the following indexes:
      #   - secret:instances (ZADD score=created member=objid)
      #   - secret:objid_lookup (HSET objid -> "objid")
      #
      # Secrets have minimal indexes since they are ephemeral and
      # accessed primarily by key, not through listings or lookups.
      #
      # Usage in Kiba job:
      #   transform Secret::IndexGenerator, stats: stats
      #
      class IndexGenerator < IndexGeneratorBase
        def generate_indexes(record)
          commands = []
          objid = record[:objid]
          created = extract_created(record)

          # Instance index: secret:instances (sorted set)
          commands << zadd('secret:instances', created, objid)
          increment_stat(:secret_instance_entries)

          # ObjID lookup: secret:objid_lookup
          commands << hset('secret:objid_lookup', objid, objid)
          increment_stat(:secret_objid_lookups)

          commands
        end
      end
    end
  end
end
