# migrations/2026-01-28/lib/migration.rb
#
# frozen_string_literal: true

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
    'receipt' => 'rc',
    'secret' => 'se',
  }.freeze

  # Model-specific output directories
  MODEL_DIRS = {
    'customer' => 'customer',
    'customdomain' => 'customdomain',
    'organization' => 'organization',
    'receipt' => 'receipt',
    'secret' => 'secret',
  }.freeze

  # Map key prefixes to model names and their source/target databases.
  # Used by RedisSource for extraction and RedisDestination for loading.
  # Format: prefix => { model: output_name, db: database_number }
  MODEL_MAPPING = {
    'customer' => { model: 'customer', db: 6 },
    'customdomain' => { model: 'customdomain', db: 6 },
    'onetime' => { model: 'customer', db: 6 },  # legacy: onetime:customer instances
    'metadata' => { model: 'metadata', db: 7 },  # becomes receipt
    'secret' => { model: 'secret', db: 8 },
    'feedback' => { model: 'feedback', db: 11 },
  }.freeze

  # Databases containing migration data
  MIGRATION_DBS = [6, 7, 8, 11].freeze

  # Target databases for V2 models
  V2_MODEL_DBS = {
    'customer' => 6,
    'organization' => 6,
    'customdomain' => 6,
    'receipt' => 7,
    'secret' => 8,
  }.freeze
end

# Load shared utilities
require_relative 'shared/uuid_v7_generator'
require_relative 'shared/redis_temp_key'
require_relative 'shared/lookup_registry'

# Load schemas
require_relative 'schemas/base'
require_relative 'schemas/v1/customer'
require_relative 'schemas/v1/customdomain'
require_relative 'schemas/v1/metadata'
require_relative 'schemas/v1/secret'
require_relative 'schemas/v2/customer'
require_relative 'schemas/v2/customdomain'
require_relative 'schemas/v2/organization'
require_relative 'schemas/v2/receipt'
require_relative 'schemas/v2/secret'

# Load sources
require_relative 'sources/jsonl_source'
require_relative 'sources/redis_source'

# Load transforms
require_relative 'transforms/base_transform'
require_relative 'transforms/index_generator_base'
require_relative 'transforms/schema_validator'
require_relative 'transforms/redis_dump_decoder'
require_relative 'transforms/redis_dump_encoder'
require_relative 'transforms/customer/identifier_enricher'
require_relative 'transforms/customer/field_transformer'
require_relative 'transforms/customer/index_generator'
require_relative 'transforms/customdomain/field_transformer'
require_relative 'transforms/customdomain/index_generator'
require_relative 'transforms/organization/generator'
require_relative 'transforms/organization/index_generator'
require_relative 'transforms/receipt/field_transformer'
require_relative 'transforms/receipt/index_generator'
require_relative 'transforms/secret/field_transformer'
require_relative 'transforms/secret/index_generator'

# Load destinations
require_relative 'destinations/jsonl_destination'
require_relative 'destinations/lookup_destination'
require_relative 'destinations/composite_destination'
require_relative 'destinations/routing_destination'
require_relative 'destinations/redis_destination'
require_relative 'destinations/redis_index_destination'
