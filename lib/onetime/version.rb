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

    def self.increment!(msg = nil)
      load_config
      @version[:BUILD] = (@version[:BUILD] || '000').to_s.succ!.to_s
      @version[:STAMP] = Time.now.utc.to_i
      OT.to_file @version.to_yaml, File.join(OT::HOME, 'BUILD.yml'), 'w'
      @version
    end

    def self.load_config
      return if @version

      require 'yaml'
      @version = YAML.load_file(File.join(OT::HOME, 'BUILD.yml'))
    end
  end
end
