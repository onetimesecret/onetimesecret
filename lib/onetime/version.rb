# lib/onetime/version.rb
#
# frozen_string_literal: true

require 'familia/json_serializer'

module Onetime
  module VERSION
    def self.to_a
      load_config
      [@version[:MAJOR], @version[:MINOR], @version[:PATCH]]
    end

    def self.to_s
      version = to_a.join('.')
      version = "#{version}-#{@version[:PRE]}" if @version[:PRE]
      version
    end

    def self.details
      load_config
      build = (@version || {}).fetch(:BUILD, nil).to_s
      build.empty? ? to_s : "#{self} (#{build})"
    end

    def self.load_config
      return if @version

      # Load version from package.json
      package_json_path = File.join(Onetime::HOME, 'package.json')
      package_json      = Familia::JsonSerializer.parse(File.read(package_json_path))

      # Split the version string into main version and pre-release parts
      version_parts      = package_json['version'].split('-')
      main_version_parts = version_parts[0].split('.')

      @version = {
        MAJOR: main_version_parts[0],
        MINOR: main_version_parts[1],
        PATCH: main_version_parts[2],
        PRE: version_parts[1], # Pre-release version if present
        BUILD: get_build_info,
      }
    end

    def self.get_build_info
      # Get the commit hash from .commit_hash.txt or git directly
      commit_hash_file = File.join(Onetime::HOME, '.commit_hash.txt')
      commit_hash      = nil

      # Try reading from file first
      if File.exist?(commit_hash_file)
        file_content = File.read(commit_hash_file).strip
        # Use file content only if it's a real commit hash (not a fallback value)
        commit_hash  = file_content unless %w[dev pristine].include?(file_content)
      end

      # If no valid hash from file, try git directly (works in local development)
      if commit_hash.nil? || commit_hash.empty?
        commit_hash = `git rev-parse --short HEAD 2>/dev/null`.strip
        commit_hash = nil if commit_hash.empty? || !$?.success?
      end

      # Final fallback for non-git environments (e.g., Docker without git)
      commit_hash || 'dev'
    end

    # HTTP User-Agent string for outbound requests (webhooks, etc.)
    # Format: OnetimeWorker/VERSION (Ruby/RUBY_VERSION)
    # @return [String] User-Agent header value
    def self.user_agent
      "OnetimeWorker/#{self} (Ruby/#{RUBY_VERSION})"
    end
  end
end
