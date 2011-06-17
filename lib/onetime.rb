
require 'syslog'
SYSLOG = Syslog.open('onetime') unless defined?(SYSLOG)

require 'gibbler'
Gibbler.secret = "(I AM THE ONE TRUE SECRET!)"

require 'familia'
require 'storable'

module Onetime
  
  def self.conf
    {
      :host => 'localhost:7143',
      :ssl => false
    }
  end
  
  class Secret < Storable
    include Familia
    include Gibbler::Complex
    index :key
    field :kind
    field :key
    field :value
    field :state
    field :paired_key
    attr_reader :entropy
    gibbler :kind, :entropy
    include Familia::Stamps
    def initialize kind=nil, entropy=nil
      unless kind.nil? || [:private, :shared].member?(kind.to_s.to_sym)
        raise ArgumentError, "Bad kind: #{kind}"
      end
      @state = :new
      @kind, @entropy = kind, entropy
    end
    def key
      @key ||= gibbler.base(36)
      @key
    end
    def load_pair
      ret = self.class.from_redis paired_key
      ret
    end
    def self.generate_pair entropy
      entropy = [entropy, Time.now.to_f * $$].flatten
      psecret, ssecret = new(:private, entropy), new(:shared, entropy)
      psecret.paired_key, ssecret.paired_key = ssecret.key, psecret.key
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

Onetime::Secret.db 0
Kernel.srand