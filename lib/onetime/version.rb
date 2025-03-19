require 'json'

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
      build.empty? ? to_s : "#{to_s} (#{build})"
    end

    def self.load_config
      return if @version

      # Load version from package.json
      package_json_path = File.join(OT::HOME, 'package.json')
      package_json = JSON.parse(File.read(package_json_path))

      # Split the version string into main version and pre-release parts
      version_parts = package_json['version'].split('-')
      main_version_parts = version_parts[0].split('.')

      @version = {
        MAJOR: main_version_parts[0],
        MINOR: main_version_parts[1],
        PATCH: main_version_parts[2],
        PRE: version_parts[1], # Pre-release version if present
        BUILD: get_build_info
      }
    end

    def self.get_build_info
      # Get the commit hash from .commit_hash.txt
      commit_hash_file = File.join(OT::HOME, '.commit_hash.txt')
      commit_hash = 'pristine'
      if File.exist?(commit_hash_file)
        commit_hash = File.read(commit_hash_file).strip
      else
        $stderr.puts "Warning: Commit hash file not found. Using default value '#{commit_hash}'."
      end
      commit_hash
    end
  end
end
