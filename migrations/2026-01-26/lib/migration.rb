# frozen_string_literal: true

# Migration Pipeline Library
#
# Shared infrastructure for Redis data migration scripts.
# Provides lookup management, Redis operations, base transformer class,
# and phase tracking.
#
# Usage:
#   require_relative 'lib/migration'
#
#   class MyTransformer < Migration::TransformerBase
#     PHASE = 1
#     MODEL_NAME = 'customer'
#     # ...
#   end
#

require_relative 'lookup_registry'
require_relative 'redis_helper'
require_relative 'transformer_base'
require_relative 'phase_manifest'

module Migration
  VERSION = '1.0.0'

  # Convenience method to create a new lookup registry.
  #
  # @param exports_dir [String] Base exports directory
  # @return [LookupRegistry]
  #
  def self.lookup_registry(exports_dir: 'exports')
    LookupRegistry.new(exports_dir: exports_dir)
  end

  # Convenience method to create a new Redis helper.
  #
  # @param redis_url [String] Redis URL
  # @param temp_db [Integer] Temporary database number
  # @return [RedisHelper]
  #
  def self.redis_helper(redis_url: 'redis://127.0.0.1:6379', temp_db: 15)
    RedisHelper.new(redis_url: redis_url, temp_db: temp_db)
  end

  # Convenience method to create a new phase manifest.
  #
  # @param exports_dir [String] Base exports directory
  # @return [PhaseManifest]
  #
  def self.manifest(exports_dir: 'exports')
    PhaseManifest.new(exports_dir: exports_dir)
  end

  # Check migration status.
  #
  # @param exports_dir [String] Base exports directory
  #
  def self.status(exports_dir: 'exports')
    manifest(exports_dir: exports_dir).print_status
  end
end
