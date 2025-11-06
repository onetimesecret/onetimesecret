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

    def self.inspect
      load_config
      build = (@version || {}).fetch(:BUILD, nil).to_s
      build.empty? ? to_s : "#{self} (#{build})"
    end

    def self.load_config
      return if @version

      # Load version from package.json
      package_json_path = File.join(Onetime::HOME, 'package.json')
      package_json      = Familia::JsonSerializer.parse(File.read(package_json_path, encoding: 'UTF-8'))

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
      # Get the commit hash from .commit_hash.txt
      commit_hash_file = File.join(Onetime::HOME, '.commit_hash.txt')
      commit_hash      = 'pristine'
      if File.exist?(commit_hash_file)
        commit_hash = File.read(commit_hash_file, encoding: 'UTF-8').strip
      else
        warn "Warning: Commit hash file not found. Using default value '#{commit_hash}'."
      end
      commit_hash
    end
  end
end
