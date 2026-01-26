# frozen_string_literal: true

require_relative 'base_transformer'

module Transformers
  # Transforms secret:* keys from v1 to v2 format.
  # Preserves email notification records, passes through secret objects.
  class SecretTransformer < BaseTransformer
    def default_stats
      { scanned: 0, transformed: 0, skipped: 0 }
    end

    def route(record, key)
      case key
      when /^secret:([^:]+):object$/
        transform_secret(record, Regexp.last_match(1))
      when /^secret:([^:]+):email$/
        # Preserve email notification records as-is
        record
      else
        skip_other_key
      end
    end

    private

    def transform_secret(record, secret_id)
      @stats[:scanned] += 1

      # Secret key pattern unchanged
      # Field transformations (custid->owner_id, remove original_size)
      # happen at load time

      @stats[:transformed] += 1

      {
        key: record['key'],
        type: record['type'],
        ttl_ms: record['ttl_ms'],
        dump: record['dump'],
        migration: {
          secret_id: secret_id,
          # The actual custid->owner_id mapping happens at load time
          email_to_objid_mapping: email_to_objid,
        },
      }
    end
  end
end
