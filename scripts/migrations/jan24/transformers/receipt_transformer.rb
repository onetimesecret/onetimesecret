# frozen_string_literal: true

require_relative 'base_transformer'

module Transformers
  # Transforms metadata:* keys to receipt:* keys (v1->v2 rename).
  class ReceiptTransformer < BaseTransformer
    def default_stats
      { scanned: 0, transformed: 0, skipped: 0 }
    end

    def route(record, key)
      case key
      when /^metadata:([^:]+):object$/
        transform_receipt(record, Regexp.last_match(1))
      else
        skip_other_key
      end
    end

    private

    def transform_receipt(record, receipt_id)
      @stats[:scanned] += 1

      # Key transformation: metadata:{id}:object -> receipt:{id}:object
      new_key = "receipt:#{receipt_id}:object"

      @stats[:transformed] += 1

      {
        key: new_key,
        original_key: record['key'],
        type: record['type'],
        ttl_ms: record['ttl_ms'],
        dump: record['dump'],
        migration: {
          v1_key: record['key'],
          receipt_id: receipt_id,
          # The actual custid->owner_id mapping happens at load time
          email_to_objid_mapping: email_to_objid,
          email_to_org_mapping: email_to_org_objid,
        },
      }
    end
  end
end
