
require 'syslog'
SYSLOG = Syslog.open('onetime') unless defined?(SYSLOG)

require 'gibbler'
Gibbler.secret = "(I AM THE ONE TRUE SECRET!)"

require 'familia'
require 'storable'

module Onetime
  
  class Secret < Storable
    include Familia
    include Gibbler::Complex
    index :key
    field :kind
    field :key
    field :value
    field :paired_key
    attr_reader :entropy
    gibbler :kind, :entropy
    include Familia::Stamps
    def initialize kind, entropy=nil
      unless [:private, :shared].member?(kind.to_s.to_sym)
        raise ArgumentError, "Bad kind: #{kind}"
      end
      @kind, @entropy = kind, entropy
      @key = gibbler.base(36)
    end
    def self.generate_pair entropy
      entropy = [entropy, Time.now.to_f * $$].flatten
      psecret, ssecret = new(:private, entropy), new(:shared, entropy)
      psecret.paired_key = ssecret.key
      ssecret.paired_key = psecret.key
      [psecret, ssecret]
    end
  end
  
  module Utils
    extend self
    unless defined?(VALID_CHARS)
      VALID_CHARS = [("a".."z").to_a, ("A".."Z").to_a, ("0".."9").to_a, %w[* $ ! ? ( )]].flatten
      VALID_CHARS_SAFE = VALID_CHARS.clone
      VALID_CHARS_SAFE.delete_if { |v| %w(i l o 1 0).member?(v) }
      VALID_CHARS.freeze
      VALID_CHARS_SAFE.freeze
    end
    def strand(len=12, safe=true)
      chars = safe ? VALID_CHARS_SAFE : VALID_CHARS
      (1..len).collect { chars[rand(chars.size-1)] }.join
    end
  end

end

Kernel.srand