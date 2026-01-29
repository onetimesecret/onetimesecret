# frozen_string_literal: true

# Kiba ETL Migration Pipeline
#
# Namespace and configuration for the Kiba-based migration pipeline.
# This module provides shared configuration, constants, and convenience
# methods for all pipeline components.
#
# Usage:
#   require_relative 'lib/migration'
#
#   Migration::Config.exports_dir = 'exports'
#   Migration::Config.redis_url = 'redis://127.0.0.1:6379'

module Migration
  VERSION = '0.1.0'

  # Centralized configuration for the migration pipeline
  module Config
    class << self
      attr_accessor :exports_dir, :redis_url, :temp_db, :dry_run

      def reset!
        @exports_dir = 'exports'
        @redis_url = 'redis://127.0.0.1:6379'
        @temp_db = 15
        @dry_run = false
      end

      def lookups_dir
        File.join(exports_dir, 'lookups')
      end
    end

    # Initialize defaults
    reset!
  end

  # ExtID prefixes by model type (ObjectIdentifier only)
  EXTID_PREFIXES = {
    'customer' => 'ur',
    'customdomain' => 'cd',
    'organization' => 'on',
  }.freeze

  # Model-specific output directories
  MODEL_DIRS = {
    'customer' => 'customer',
    'customdomain' => 'customdomain',
    'organization' => 'organization',
    'receipt' => 'receipt',
    'secret' => 'secret',
  }.freeze
end

# Load shared utilities
require_relative 'shared/uuid_v7_generator'
require_relative 'shared/redis_temp_key'
require_relative 'shared/lookup_registry'

# Load schemas
require_relative 'schemas/base'
require_relative 'schemas/v1/customer'
require_relative 'schemas/v2/customer'

# Load sources
require_relative 'sources/jsonl_source'

# Load transforms
require_relative 'transforms/base_transform'
require_relative 'transforms/schema_validator'
require_relative 'transforms/redis_dump_decoder'
require_relative 'transforms/redis_dump_encoder'
require_relative 'transforms/customer/identifier_enricher'
require_relative 'transforms/customer/field_transformer'

# Load destinations
require_relative 'destinations/jsonl_destination'
require_relative 'destinations/lookup_destination'
require_relative 'destinations/composite_destination'
