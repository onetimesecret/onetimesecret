# frozen_string_literal: true

require_relative 'base'

module IndexRebuilder
  # Builds Receipt model indexes:
  # - receipt:instances (zset: objid -> created)
  # - receipt:expiration_timeline (zset: expires date -> objid)
  # - receipt:objid_lookup (hash: objid -> objid JSON serialized string)
  class ReceiptIndexes < Base
    def build_all
      build_instances
    end

    def build_instances
      build_instances_set('receipt', 'receipt')
    end
  end
end
