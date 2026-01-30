# migrations/2026-01-27/lib/migration.rb
#
# frozen_string_literal: true

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

  # Default results directory (relative to this file)
  DEFAULT_RESULTS_DIR = File.join(File.expand_path('../..', __FILE__), 'results')

  # Convenience method to create a new lookup registry.
  #
  # @param results_dir [String] Base results directory
  # @return [LookupRegistry]
  #
  def self.lookup_registry(results_dir: DEFAULT_RESULTS_DIR)
    LookupRegistry.new(results_dir: results_dir)
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
  # @param results_dir [String] Base results directory
  # @return [PhaseManifest]
  #
  def self.manifest(results_dir: DEFAULT_RESULTS_DIR)
    PhaseManifest.new(results_dir: results_dir)
  end

  # Check migration status.
  #
  # @param results_dir [String] Base results directory
  #
  def self.status(results_dir: DEFAULT_RESULTS_DIR)
    manifest(results_dir: results_dir).print_status
  end
end
