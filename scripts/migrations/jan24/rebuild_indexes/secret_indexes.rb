# frozen_string_literal: true

require_relative 'base'

module IndexRebuilder
  # Builds Secret model indexes:
  # - secret:instances (zset: objid -> created)
  # - secret:objid_lookup (hash: objid -> objid JSON serialized string)
  class SecretIndexes < Base
    def build_all
      build_instances
    end

    def build_instances
      build_instances_set('secret', 'secret')
    end
  end
end
