# migrations/2026-01-27/lib/phase_manifest.rb
#
# frozen_string_literal: true

require 'json'
require 'fileutils'

module Migration
  # Tracks phase completion for the migration pipeline.
  #
  # Maintains a manifest file (results/manifest.json) recording:
  # - Which phases have completed
  # - Timestamps for each phase
  # - Record counts (input/output)
  # - Error counts
  #
  # This enables:
  # - Resumable migrations (skip completed phases)
  # - Dependency validation (phase N requires phase N-1)
  # - Audit trail for migration runs
  #
  # Manifest Format:
  #   {
  #     "version": "1.0",
  #     "started_at": "2026-01-28T12:00:00Z",
  #     "phases": {
  #       "1": {
  #         "name": "customer",
  #         "status": "completed",
  #         "started_at": "2026-01-28T12:00:00Z",
  #         "completed_at": "2026-01-28T12:05:00Z",
  #         "records_in": 1000,
  #         "records_out": 1000,
  #         "errors": 0
  #       }
  #     }
  #   }
  #
  # Usage:
  #   manifest = Migration::PhaseManifest.new(results_dir: 'results')
  #
  #   # Check if a phase is complete
  #   manifest.phase_complete?(2)  # => false
  #
  #   # Validate dependencies before running phase 3
  #   manifest.validate_dependencies!(3)  # Raises if phase 1 or 2 incomplete
  #
  #   # Mark a phase complete
  #   manifest.complete_phase(phase: 1, name: 'customer', records_in: 1000, records_out: 1000)
  #
  class PhaseManifest
    MANIFEST_VERSION = '1.0'
    MANIFEST_FILE = 'manifest.json'

    # Phase dependencies: phase_number => [required_phases]
    PHASE_DEPENDENCIES = {
      1 => [],           # Customer: no dependencies
      2 => [1],          # Organization: requires Customer
      3 => [1, 2],       # CustomDomain: requires Customer, Organization
      4 => [1, 2, 3],    # Receipt: requires Customer, Organization, CustomDomain
      5 => [1, 2, 3],    # Secret: requires Customer, Organization, CustomDomain
    }.freeze

    # Phase names for display
    PHASE_NAMES = {
      1 => 'customer',
      2 => 'organization',
      3 => 'customdomain',
      4 => 'receipt',
      5 => 'secret',
    }.freeze

    attr_reader :results_dir, :manifest_path

    def initialize(results_dir: nil)
      # Default to the results directory within this migration folder
      @results_dir = results_dir || File.join(File.expand_path('../..', __dir__), 'results')
      @manifest_path = File.join(@results_dir, MANIFEST_FILE)
      @data = nil
    end

    # Load manifest from disk (creates if doesn't exist).
    #
    # @return [Hash] Manifest data
    #
    def load
      @data ||= begin
        if File.exist?(@manifest_path)
          JSON.parse(File.read(@manifest_path))
        else
          new_manifest
        end
      end
    end

    # Save manifest to disk.
    #
    def save
      FileUtils.mkdir_p(@results_dir)
      File.write(@manifest_path, JSON.pretty_generate(load))
    end

    # Check if a phase is complete.
    #
    # @param phase [Integer] Phase number
    # @return [Boolean]
    #
    def phase_complete?(phase)
      load
      phase_data = @data['phases'][phase.to_s]
      phase_data && phase_data['status'] == 'completed'
    end

    # Check if a phase is in progress.
    #
    # @param phase [Integer] Phase number
    # @return [Boolean]
    #
    def phase_in_progress?(phase)
      load
      phase_data = @data['phases'][phase.to_s]
      phase_data && phase_data['status'] == 'in_progress'
    end

    # Validate that all dependencies for a phase are met.
    #
    # @param phase [Integer] Phase number to validate
    # @raise [PhaseDependencyError] If any dependency is not complete
    #
    def validate_dependencies!(phase)
      required = PHASE_DEPENDENCIES[phase] || []
      missing = required.reject { |p| phase_complete?(p) }

      return if missing.empty?

      raise PhaseDependencyError.new(
        phase,
        missing: missing,
        phase_names: PHASE_NAMES
      )
    end

    # Mark a phase as started.
    #
    # @param phase [Integer] Phase number
    # @param name [String] Phase name
    #
    def start_phase(phase:, name:)
      load
      @data['phases'][phase.to_s] = {
        'name' => name,
        'status' => 'in_progress',
        'started_at' => Time.now.utc.iso8601,
      }
      save
    end

    # Mark a phase as complete.
    #
    # @param phase [Integer] Phase number
    # @param name [String] Phase name
    # @param records_in [Integer] Number of input records
    # @param records_out [Integer] Number of output records
    # @param errors [Integer] Number of errors (default: 0)
    #
    def complete_phase(phase:, name:, records_in:, records_out:, errors: 0)
      load
      existing = @data['phases'][phase.to_s] || {}

      @data['phases'][phase.to_s] = existing.merge(
        'name' => name,
        'status' => 'completed',
        'completed_at' => Time.now.utc.iso8601,
        'records_in' => records_in,
        'records_out' => records_out,
        'errors' => errors
      )
      save
    end

    # Mark a phase as failed.
    #
    # @param phase [Integer] Phase number
    # @param name [String] Phase name
    # @param error [String] Error message
    #
    def fail_phase(phase:, name:, error:)
      load
      existing = @data['phases'][phase.to_s] || {}

      @data['phases'][phase.to_s] = existing.merge(
        'name' => name,
        'status' => 'failed',
        'failed_at' => Time.now.utc.iso8601,
        'error' => error
      )
      save
    end

    # Get status of a specific phase.
    #
    # @param phase [Integer] Phase number
    # @return [Hash, nil] Phase data or nil if not started
    #
    def phase_status(phase)
      load
      @data['phases'][phase.to_s]
    end

    # Get summary of all phases.
    #
    # @return [Array<Hash>] Array of phase summaries
    #
    def summary
      load
      PHASE_NAMES.map do |phase_num, default_name|
        phase_data = @data['phases'][phase_num.to_s]
        {
          phase: phase_num,
          name: phase_data&.dig('name') || default_name,
          status: phase_data&.dig('status') || 'pending',
          records_in: phase_data&.dig('records_in'),
          records_out: phase_data&.dig('records_out'),
          errors: phase_data&.dig('errors'),
        }
      end
    end

    # Print a human-readable status report.
    #
    def print_status
      puts "Migration Manifest: #{@manifest_path}"
      puts "Version: #{load['version']}"
      puts "Started: #{@data['started_at'] || 'Not started'}"
      puts
      puts 'Phase Status:'
      puts '-' * 60

      summary.each do |phase|
        status_icon = case phase[:status]
                      when 'completed' then '[OK]'
                      when 'in_progress' then '[..]'
                      when 'failed' then '[!!]'
                      else '[ ]'
                      end

        counts = if phase[:records_in]
                   "(#{phase[:records_in]} in -> #{phase[:records_out]} out, #{phase[:errors] || 0} errors)"
                 else
                   ''
                 end

        puts "  #{status_icon} Phase #{phase[:phase]}: #{phase[:name]} #{counts}"
      end
    end

    # Reset manifest (for testing or re-running).
    #
    def reset!
      @data = new_manifest
      save
    end

    # Get the next pending phase number.
    #
    # @return [Integer, nil] Next phase to run, or nil if all complete
    #
    def next_phase
      PHASE_NAMES.keys.sort.find { |p| !phase_complete?(p) }
    end

    private

    def new_manifest
      {
        'version' => MANIFEST_VERSION,
        'started_at' => Time.now.utc.iso8601,
        'phases' => {},
      }
    end

    # Custom error classes
    class ManifestError < StandardError; end

    class PhaseDependencyError < ManifestError
      attr_reader :phase, :missing_phases

      def initialize(phase, missing:, phase_names:)
        @phase = phase
        @missing_phases = missing

        missing_names = missing.map { |p| "#{p} (#{phase_names[p]})" }.join(', ')
        super(
          "Phase #{phase} requires phases [#{missing_names}] to be complete first."
        )
      end
    end
  end
end
