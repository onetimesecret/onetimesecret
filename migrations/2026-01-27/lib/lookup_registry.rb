# migrations/2026-01-27/lib/lookup_registry.rb
#
# frozen_string_literal: true

require 'json'

module Migration
  # Central registry for lookup data used across migration phases.
  #
  # Provides a unified interface for loading, storing, and querying lookup
  # mappings. Supports lazy loading, phase prerequisite validation, and
  # automatic bidirectional lookup generation.
  #
  # Design Goals:
  # - Single JSON format for all lookups in exports/lookups/
  # - Lazy loading with phase prerequisite validation
  # - Auto-generate bidirectional lookups when registered
  # - Fail-fast on missing prerequisites (no silent failures)
  #
  # Usage:
  #   registry = Migration::LookupRegistry.new(exports_dir: 'exports')
  #
  #   # Register lookup data from a prior phase
  #   registry.register(:email_to_customer, data, phase: 1)
  #
  #   # Require a lookup for the current phase (fails if missing)
  #   registry.require_lookup(:email_to_customer, for_phase: 3)
  #
  #   # Perform lookups
  #   customer_objid = registry.lookup(:email_to_customer, 'user@example.com')
  #
  class LookupRegistry
    # Standard lookup directory within exports
    LOOKUPS_DIR = 'lookups'

    # Known lookup types and their expected files
    # Maps logical name -> { file:, phase:, description: }
    KNOWN_LOOKUPS = {
      email_to_customer: {
        file: 'email_to_customer_objid.json',
        phase: 1,
        description: 'Maps customer email addresses to customer objid',
      },
      email_to_org: {
        file: 'email_to_org_objid.json',
        phase: 2,
        description: 'Maps customer email addresses to organization objid',
      },
      customer_to_org: {
        file: 'customer_objid_to_org_objid.json',
        phase: 2,
        description: 'Maps customer objid to organization objid',
      },
      fqdn_to_domain: {
        file: 'fqdn_to_domain_objid.json',
        phase: 3,
        description: 'Maps display domain FQDN to custom_domain objid',
      },
    }.freeze

    attr_reader :exports_dir, :lookups_dir

    def initialize(exports_dir: 'exports')
      @exports_dir = exports_dir
      @lookups_dir = File.join(exports_dir, LOOKUPS_DIR)
      @lookups = {}
      @lookup_metadata = {}
      @loaded = Set.new
    end

    # Register lookup data with phase tracking.
    #
    # @param name [Symbol] Lookup name (e.g., :email_to_customer)
    # @param data [Hash] The lookup hash mapping keys to values
    # @param phase [Integer] The phase number that produced this lookup
    # @return [Hash] The registered data
    #
    def register(name, data, phase:)
      name = name.to_sym
      @lookups[name] = data.freeze
      @lookup_metadata[name] = {
        phase: phase,
        count: data.size,
        registered_at: Time.now,
      }
      @loaded << name
      data
    end

    # Load a lookup from disk.
    #
    # @param name [Symbol] Lookup name
    # @param file [String, nil] Override file path (default: use KNOWN_LOOKUPS)
    # @return [Hash] The loaded lookup data
    # @raise [LookupNotFoundError] If file doesn't exist
    #
    def load(name, file: nil)
      name = name.to_sym
      return @lookups[name] if @loaded.include?(name)

      file_path = resolve_file_path(name, file)

      unless File.exist?(file_path)
        raise LookupNotFoundError.new(name, file_path)
      end

      data = JSON.parse(File.read(file_path))
      known = KNOWN_LOOKUPS[name]
      phase = known ? known[:phase] : 0

      register(name, data, phase: phase)
    end

    # Require a lookup for a specific phase, validating prerequisites.
    #
    # @param name [Symbol] Lookup name
    # @param for_phase [Integer] The phase requiring this lookup
    # @param file [String, nil] Override file path
    # @return [Hash] The lookup data
    # @raise [PhasePrerequisiteError] If lookup's phase >= for_phase
    # @raise [LookupNotFoundError] If lookup file doesn't exist
    #
    def require_lookup(name, for_phase:, file: nil)
      name = name.to_sym
      data = load(name, file: file)
      meta = @lookup_metadata[name]

      if meta && meta[:phase] >= for_phase
        raise PhasePrerequisiteError.new(
          name,
          required_by_phase: for_phase,
          produced_in_phase: meta[:phase]
        )
      end

      data
    end

    # Perform a lookup.
    #
    # @param name [Symbol] Lookup name
    # @param key [String] The key to look up
    # @param strict [Boolean] If true, raise on missing key (default: false)
    # @return [String, nil] The looked-up value, or nil if not found
    # @raise [LookupKeyNotFoundError] If strict and key not found
    #
    def lookup(name, key, strict: false)
      name = name.to_sym
      data = @lookups[name]

      unless data
        raise LookupNotLoadedError.new(name) if strict
        return nil
      end

      value = data[key.to_s]

      if value.nil? && strict
        raise LookupKeyNotFoundError.new(name, key)
      end

      value
    end

    # Perform a lookup with failure tracking for stats.
    #
    # @param name [Symbol] Lookup name
    # @param key [String] The key to look up
    # @param stats [Hash] Stats hash with :failed_*_lookups array
    # @param stats_key [Symbol] Key in stats hash for tracking failures
    # @return [String, nil] The looked-up value
    #
    def lookup_with_tracking(name, key, stats:, stats_key:)
      value = lookup(name, key, strict: false)
      if value.nil? && key && !key.empty?
        stats[stats_key] ||= []
        stats[stats_key] << key
      end
      value
    end

    # Save lookup data to disk.
    #
    # @param name [Symbol] Lookup name
    # @param data [Hash] The lookup data (defaults to registered data)
    # @param file [String, nil] Override file path
    #
    def save(name, data: nil, file: nil)
      name = name.to_sym
      data ||= @lookups[name]

      raise "No data for lookup #{name}" unless data

      file_path = resolve_file_path(name, file)
      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, JSON.pretty_generate(data))
    end

    # Generate bidirectional lookup from existing lookup.
    #
    # @param source [Symbol] Source lookup name
    # @param target [Symbol] Target (reverse) lookup name
    # @param phase [Integer] Phase for the new lookup
    # @return [Hash] The reverse lookup data
    #
    def generate_reverse(source, target, phase:)
      source_data = @lookups[source.to_sym]
      raise LookupNotLoadedError.new(source) unless source_data

      reverse_data = source_data.invert
      register(target, reverse_data, phase: phase)
    end

    # Check if a lookup is loaded.
    #
    # @param name [Symbol] Lookup name
    # @return [Boolean]
    #
    def loaded?(name)
      @loaded.include?(name.to_sym)
    end

    # Get metadata about a lookup.
    #
    # @param name [Symbol] Lookup name
    # @return [Hash, nil] Metadata hash or nil
    #
    def metadata(name)
      @lookup_metadata[name.to_sym]
    end

    # List all loaded lookups with their metadata.
    #
    # @return [Hash] lookup_name -> metadata
    #
    def list
      @lookup_metadata.dup
    end

    # Clear all loaded lookups (useful for testing).
    #
    def clear!
      @lookups.clear
      @lookup_metadata.clear
      @loaded.clear
    end

    private

    def resolve_file_path(name, override_file)
      return File.expand_path(override_file) if override_file

      known = KNOWN_LOOKUPS[name.to_sym]
      if known
        File.join(@lookups_dir, known[:file])
      else
        File.join(@lookups_dir, "#{name}.json")
      end
    end

    # Custom error classes for better error handling
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
          "cannot be required by phase #{required_by_phase}. " \
          "A phase cannot depend on lookups from the same or later phases."
        )
      end
    end
  end
end
