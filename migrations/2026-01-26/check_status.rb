#!/usr/bin/env ruby
# frozen_string_literal: true

# Check migration status and validate phase dependencies.
#
# Usage:
#   ruby check_status.rb                    # Show status of all phases
#   ruby check_status.rb --phase=3          # Validate dependencies for phase 3
#   ruby check_status.rb --reset            # Reset manifest (start fresh)
#   ruby check_status.rb --next             # Show next pending phase
#

require_relative 'lib/migration'

def parse_args(args)
  options = {
    exports_dir: 'exports',
    phase: nil,
    reset: false,
    next_phase: false,
  }

  args.each do |arg|
    case arg
    when /^--exports-dir=(.+)$/
      options[:exports_dir] = Regexp.last_match(1)
    when /^--phase=(\d+)$/
      options[:phase] = Regexp.last_match(1).to_i
    when '--reset'
      options[:reset] = true
    when '--next'
      options[:next_phase] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby check_status.rb [OPTIONS]

        Check migration status and validate phase dependencies.

        Options:
          --exports-dir=DIR   Exports directory (default: exports)
          --phase=N           Validate dependencies for phase N
          --next              Show next pending phase
          --reset             Reset manifest (start fresh)
          --help              Show this help

        Examples:
          ruby check_status.rb                  # Show status
          ruby check_status.rb --phase=3       # Can we run phase 3?
          ruby check_status.rb --next          # What's next?
      HELP
      exit 0
    else
      warn "Unknown option: #{arg}"
      exit 1
    end
  end

  options
end

options = parse_args(ARGV)
manifest = Migration::PhaseManifest.new(exports_dir: options[:exports_dir])

if options[:reset]
  print "Reset manifest? This will clear all phase tracking. [y/N] "
  answer = $stdin.gets&.strip
  if answer&.downcase == 'y'
    manifest.reset!
    puts "Manifest reset."
  else
    puts "Cancelled."
  end
  exit 0
end

if options[:next_phase]
  next_phase = manifest.next_phase
  if next_phase
    name = Migration::PhaseManifest::PHASE_NAMES[next_phase]
    puts "Next phase: #{next_phase} (#{name})"
  else
    puts "All phases complete."
  end
  exit 0
end

if options[:phase]
  begin
    manifest.validate_dependencies!(options[:phase])
    puts "Phase #{options[:phase]} dependencies satisfied."
    puts "Ready to run phase #{options[:phase]}."
  rescue Migration::PhaseManifest::PhaseDependencyError => e
    puts "Cannot run phase #{options[:phase]}:"
    puts "  #{e.message}"
    exit 1
  end
  exit 0
end

# Default: show status
manifest.print_status
