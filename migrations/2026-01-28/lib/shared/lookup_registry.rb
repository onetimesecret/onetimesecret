# frozen_string_literal: true

require 'json'
require 'fileutils'

module Migration
  module Shared
    # Central registry for lookup data used across migration phases.
    #
    # Simplified version for Kiba pipeline - focuses on:
    # - Loading lookups from JSON files
    # - Phase prerequisite validation
    # - Collecting lookup data during transforms
    #
    # Usage:
    #   registry = LookupRegistry.new
    #
    #   # Require lookups for current phase (fails if missing)
    #   registry.require_lookup(:email_to_customer, for_phase: 4)
    #
    #   # Perform lookups
    #   objid = registry.lookup(:email_to_customer, 'user@example.com')
    #
    #   # Collect data during transform
    #   registry.collect(:email_to_customer, email, objid)
    #
    #   # Save collected data
    #   registry.save(:email_to_customer)
    #
    class LookupRegistry
      LOOKUPS_DIR = 'lookups'

      # Known lookup types with metadata
      KNOWN_LOOKUPS = {
        email_to_customer: {
          file: 'email_to_customer_objid.json',
          phase: 1,
          description: 'Maps customer email to customer objid',
        },
        email_to_org: {
          file: 'email_to_org_objid.json',
          phase: 2,
          description: 'Maps customer email to organization objid',
        },
        customer_to_org: {
          file: 'customer_objid_to_org_objid.json',
          phase: 2,
          description: 'Maps customer objid to organization objid',
        },
        fqdn_to_domain: {
          file: 'fqdn_to_domain_objid.json',
          phase: 3,
          description: 'Maps FQDN to custom_domain objid',
        },
        metadata_key_to_receipt: {
          file: 'metadata_key_to_receipt_objid.json',
          phase: 4,
          description: 'Maps metadata key (secret key) to receipt objid',
        },
        secret_key_to_objid: {
          file: 'secret_key_to_objid.json',
          phase: 5,
          description: 'Maps secret key to secret objid',
        },
      }.freeze

      attr_reader :exports_dir, :lookups_dir

      def initialize(exports_dir: nil)
        @exports_dir = exports_dir || Migration::Config.exports_dir
        @lookups_dir = File.join(@exports_dir, LOOKUPS_DIR)
        @lookups = {}
        @metadata = {}
        @collected = {}
        @loaded = Set.new
      end

      # Require a lookup for a specific phase.
      #
      # @param name [Symbol] Lookup name
      # @param for_phase [Integer] The phase requiring this lookup
      # @return [Hash] The lookup data
      # @raise [PhasePrerequisiteError] If lookup phase >= for_phase
      # @raise [LookupNotFoundError] If lookup file doesn't exist
      #
      def require_lookup(name, for_phase:)
        name = name.to_sym
        data = load(name)
        meta = @metadata[name]

        if meta && meta[:phase] >= for_phase
          raise PhasePrerequisiteError.new(
            name,
            required_by_phase: for_phase,
            produced_in_phase: meta[:phase]
          )
        end

        data
      end

      # Load a lookup from disk.
      #
      # @param name [Symbol] Lookup name
      # @return [Hash] The loaded data
      #
      def load(name)
        name = name.to_sym
        return @lookups[name] if @loaded.include?(name)

        file_path = resolve_file_path(name)

        unless File.exist?(file_path)
          raise LookupNotFoundError.new(name, file_path)
        end

        data = JSON.parse(File.read(file_path))
        known = KNOWN_LOOKUPS[name]
        phase = known ? known[:phase] : 0

        register(name, data, phase: phase)
      end

      # Register lookup data.
      #
      # @param name [Symbol] Lookup name
      # @param data [Hash] The lookup hash
      # @param phase [Integer] Phase that produced this lookup
      # @return [Hash] The registered data
      #
      def register(name, data, phase:)
        name = name.to_sym
        @lookups[name] = data.freeze
        @metadata[name] = {
          phase: phase,
          count: data.size,
          registered_at: Time.now,
        }
        @loaded << name
        data
      end

      # Perform a lookup.
      #
      # @param name [Symbol] Lookup name
      # @param key [String] Key to look up
      # @param strict [Boolean] Raise on missing key
      # @return [String, nil] The value or nil
      #
      def lookup(name, key, strict: false)
        name = name.to_sym
        data = @lookups[name]

        unless data
          raise LookupNotLoadedError.new(name) if strict
          return nil
        end

        value = data[key.to_s]
        raise LookupKeyNotFoundError.new(name, key) if value.nil? && strict

        value
      end

      # Collect a key-value pair for later saving.
      #
      # @param name [Symbol] Lookup name
      # @param key [String] The key
      # @param value [String] The value
      #
      def collect(name, key, value)
        name = name.to_sym
        @collected[name] ||= {}
        @collected[name][key.to_s] = value
      end

      # Get all collected data for a lookup.
      #
      # @param name [Symbol] Lookup name
      # @return [Hash] Collected key-value pairs
      #
      def collected(name)
        @collected[name.to_sym] || {}
      end

      # Save collected lookup data to disk.
      #
      # @param name [Symbol] Lookup name
      # @param data [Hash, nil] Override data (uses collected if nil)
      #
      def save(name, data: nil)
        name = name.to_sym
        data ||= @collected[name]

        raise "No data to save for lookup #{name}" unless data && !data.empty?

        file_path = resolve_file_path(name)
        FileUtils.mkdir_p(File.dirname(file_path))
        File.write(file_path, JSON.pretty_generate(data))
      end

      # Check if a lookup is loaded.
      #
      # @param name [Symbol] Lookup name
      # @return [Boolean]
      #
      def loaded?(name)
        @loaded.include?(name.to_sym)
      end

      # Clear all data (for testing).
      #
      def clear!
        @lookups.clear
        @metadata.clear
        @collected.clear
        @loaded.clear
      end

      private

      def resolve_file_path(name)
        known = KNOWN_LOOKUPS[name.to_sym]
        if known
          File.join(@lookups_dir, known[:file])
        else
          File.join(@lookups_dir, "#{name}.json")
        end
      end

      # Error classes
      class LookupError < StandardError; end

      class LookupNotFoundError < LookupError
        attr_reader :name, :file_path

        def initialize(name, file_path)
          @name = name
          @file_path = file_path
          super("Lookup '#{name}' not found at #{file_path}")
        end
      end

      class LookupNotLoadedError < LookupError
        attr_reader :name

        def initialize(name)
          @name = name
          super("Lookup '#{name}' not loaded. Call load(:#{name}) first.")
        end
      end

      class LookupKeyNotFoundError < LookupError
        attr_reader :name, :key

        def initialize(name, key)
          @name = name
          @key = key
          super("Key '#{key}' not found in lookup '#{name}'")
        end
      end

      class PhasePrerequisiteError < LookupError
        attr_reader :name, :required_by_phase, :produced_in_phase

        def initialize(name, required_by_phase:, produced_in_phase:)
          @name = name
          @required_by_phase = required_by_phase
          @produced_in_phase = produced_in_phase
          super(
            "Lookup '#{name}' (produced in phase #{produced_in_phase}) " \
            "cannot be required by phase #{required_by_phase}."
          )
        end
      end
    end
  end
end
