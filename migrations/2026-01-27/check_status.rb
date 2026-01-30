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

require 'optparse'
require_relative 'lib/migration'

def parse_args(args)
  # Default to results subdirectory within this migration folder
  default_results_dir = File.join(File.expand_path('..', __FILE__), 'results')

  options = {
    results_dir: default_results_dir,
    phase: nil,
    reset: false,
    next_phase: false,
  }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby check_status.rb [OPTIONS]"
    opts.separator ""
    opts.separator "Check migration status and validate phase dependencies."
    opts.separator ""
    opts.separator "Options:"

    opts.on("--results-dir=DIR", "Results directory (default: results)") do |dir|
      options[:results_dir] = dir
    end

    opts.on("--phase=N", Integer, "Validate dependencies for phase N") do |n|
      options[:phase] = n
    end

    opts.on("--next", "Show next pending phase") do
      options[:next_phase] = true
    end

    opts.on("--reset", "Reset manifest (start fresh)") do
      options[:reset] = true
    end

    opts.on("--help", "Show this help") do
      puts opts
      puts ""
      puts "Examples:"
      puts "  ruby check_status.rb                  # Show status"
      puts "  ruby check_status.rb --phase=3       # Can we run phase 3?"
      puts "  ruby check_status.rb --next          # What's next?"
      exit 0
    end
  end

  begin
    parser.parse!(args)
  rescue OptionParser::InvalidOption => e
    warn e.message
    exit 1
  end

  options
end

options = parse_args(ARGV)
manifest = Migration::PhaseManifest.new(results_dir: options[:results_dir])

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
