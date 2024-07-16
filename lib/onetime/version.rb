module Onetime
  module VERSION
    def self.to_a
      load_config
      [@version[:MAJOR], @version[:MINOR], @version[:PATCH]]
    end

    def self.to_s
      to_a[0..-2].join('.')
    end

    def self.inspect
      to_a.join('.')
    end

    def self.load_config
      return if @version

      require 'yaml'
      @version = YAML.load_file(File.join(OT::HOME, 'VERSION.yml'))
    end
  end
end
