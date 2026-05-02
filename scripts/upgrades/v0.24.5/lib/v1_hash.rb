# frozen_string_literal: true

require 'base64'

module Upgrade
  # Decodes the v1 hash payload (`fields_b64`) from the typed JSONL records
  # emitted by dump_keys.rb (and propagated by upstream transforms).
  #
  # Returns a `{String => String}` hash equivalent to what HGETALL returned
  # before the cleanup. Replaces the prior RESTORE → HGETALL round-trip
  # through a temp Redis DB.
  #
  # When `fields_b64` is missing or not a Hash, the helper logs a
  # `:data_corruption` entry into the host transform's `errors_hash` (which
  # is typically `@stats[:errors]`) and returns nil. Callers must treat nil
  # as "skip this record" — emitting a hollow v2 record from an empty hash
  # would propagate corruption downstream into load_keys.rb.
  module V1Hash
    module_function

    # @param record [Hash] a JSONL record with a `:fields_b64` Hash payload
    # @param errors_hash [Hash{Symbol=>Array}] the stats errors map (must
    #   already have `:data_corruption` initialized as an Array)
    # @return [Hash{String=>String}, nil]
    def read(record, errors_hash)
      fields = record[:fields_b64]
      unless fields.is_a?(Hash)
        errors_hash[:data_corruption] << {
          key: record[:key],
          error: 'Missing fields_b64 typed payload',
        }
        return nil
      end

      fields.each_with_object({}) do |(field, b64), acc|
        acc[field.to_s] = Base64.strict_decode64(b64.to_s)
      end
    end
  end
end
