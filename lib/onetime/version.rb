module Onetime
  module VERSION
    def self.to_a
      load_config
      [@version[:MAJOR], @version[:MINOR], @version[:PATCH]]
    end

    def self.to_s
      to_a.join('.')
    end

    def self.inspect
      '%s (%s)' % [to_a.join('.'), @version[:BUILD]]
    end

    def self.load_config
      return if @version

      require 'yaml'
      @version = YAML.load_file(File.join(OT::HOME, 'VERSION.yml'))

      commit_hash = get_build_info
      @version[:BUILD] = commit_hash
      @version
    end

    def self.get_build_info
      # Get the commit hash from .commit_hash.txt
      commit_hash_file = File.join(OT::HOME, '.commit_hash.txt')
      commit_hash = 'unknown'
      if File.exist?(commit_hash_file)
        commit_hash = File.read(commit_hash_file).strip
      else
        $stderr.puts "Warning: Commit hash file not found. Using default value 'unknown'."
      end
      commit_hash
    end
  end
end
