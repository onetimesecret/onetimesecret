

class Onetime::RateLimit < Familia::String
  DEFAULT_LIMIT = 25 unless defined?(OT::RateLimit::DEFAULT_LIMIT)
  ttl 10.minutes
  def initialize identifier, event
    #super [Familia.apiversion, :limiter, identifier, event, self.class.eventstamp]
    super [:limiter, identifier, event, self.class.eventstamp], :db => 2
  end
  alias_method :count, :to_i
  class << self
    attr_reader :events
    def incr! identifier, event
      lmtr = new identifier, event
      count = lmtr.increment
      lmtr.update_expiration
      OT.ld [:limit, event, identifier, count].inspect
      raise OT::LimitExceeded.new(identifier, event, count) if exceeded?(event, count)
      count
    end
    alias_method :increment!, :incr!
    def exceeded? event, count
      (count) > (events[event] || DEFAULT_LIMIT)
    end
    def register_event event, count
      (@events ||= {})[event] = count
    end
    def register_events events
      (@events ||= {}).merge! events
    end
    def eventstamp
      now = OT.now.to_i
      rounded = now - (now % self.ttl)
      Time.at(rounded).utc.strftime('%H%M')
    end
  end
end

module Onetime::Models
  module Passphrase
    attr_accessor :passphrase_temp
    def update_passphrase v
      self.passphrase_encryption = 1
      @passphrase_temp = v
      self.passphrase = BCrypt::Password.create(v, :cost => 12).to_s
    end
    def has_passphrase?
      !passphrase.to_s.empty?
    end
    def passphrase? guess
      begin 
        ret = !has_passphrase? || BCrypt::Password.new(passphrase) == guess
        @passphrase_temp = guess if ret  # used to decrypt the value
        ret
      rescue BCrypt::Errors::InvalidHash => ex
        msg = "[old-passphrase]"
        !has_passphrase? || (!guess.to_s.empty? && passphrase.to_s.downcase.strip == guess.to_s.downcase.strip)
      end
    end
  end
  module RateLimited
    def event_incr! event
      OT::RateLimit.incr! external_identifier, event
    end
    def external_identifier
      raise RuntimeError, "TODO: #{self.class}.external_identifier"
    end
  end
  module RedisHash
    attr_accessor :prefix, :identifier, :suffix, :cache
    def name identifier=nil
      self.identifier ||= identifier
      @prefix ||= self.class.to_s.downcase.split('::').last.to_sym
      @suffix ||= :object
      Familia.rediskey prefix, self.identifier, suffix
    end
    def check_identifier!
      if self.identifier.to_s.empty?
        raise RuntimeError, "Suffix cannot be empty for #{self.class}"
      end
    end
    def destroy!
      clear
    end
    def save
      hsh = { :key => identifier }
      hsh[:created] = Time.now.to_i unless exists?
      ret = update_fields hsh
      ret == "OK"
    end
    def update_fields hsh={}
      check_identifier!
      hsh[:updated] = OT.now.to_i
      ret = update hsh
      self.cache.replace hsh
      ret
    end
    def refresh_cache
      self.cache.replace self.all unless self.identifier.to_s.empty?
    end
    def update_time!
      check_identifier!
      self.put :updated, OT.now.to_i
    end
    def cache
      @cache ||= {}
      @cache
    end
    #
    # Support for accessing ModelBase hash keys via method names.
    # e.g.
    #     s = OT::Session.new
    #     s.agent                 #=> nil
    #     s.agent = "Mozilla..."
    #     s.agent                 #=> "Mozilla..."
    #
    #     s.agent?                # raises NoMethodError
    #
    #     s.agent!                #=> "Mozilla..."
    #     s.agent!                #=> nil
    #
    # NOTA BENE: This will hit the internal cache before redis.
    #
    def method_missing meth, *args
      #OT.ld "Call to #{self.class}###{meth} (cache attempt)"
      last_char = meth.to_s[-1] 
      field = case last_char
      when '=', '!', '?'
        meth.to_s[0..-2]
      else
        meth.to_s
      end
      instance_value = instance_variable_get("@#{field}")
      refresh_cache unless !instance_value.nil? || self.cache.has_key?(field)
      ret = case last_char
      when '='
        self[field] = self.cache[field] = args.first
      when '!'
        self.delete(field) and self.cache.delete(field) # Hash#delete returns the value
      when '?'
        raise NoMethodError, "#{self.class}##{meth.to_s}"
      else
        self.cache[field] || instance_value
      end
      ret
    end
    def get_value field
      self.cache ||= {}
      self.cache[field] || self[field]
    end
  end
end

module Onetime
  module Feedback
    @values = Familia::SortedSet.new name.to_s.downcase.gsub('::', Familia.delim).to_sym, :db => 11
    class << self
      attr_reader :values
      def add msg
        self.values.add OT.now.to_i, msg
        self.values.remrangebyscore 0, OT.now.to_i-30.days
      end
      # Returns a Hash like: {"msg1"=>"1322644672", "msg2"=>"1322644668"}
      def all
        ret = self.values.revrangeraw 0, -1, :with_scores => true
        Hash[*ret]
      end
      def recent duration=30.days
        spoint, epoint = OT.now.to_i-duration, OT.now.to_i
        ret = self.values.rangebyscoreraw spoint, epoint, :with_scores => true
        Hash[*ret]
      end
    end
  end
  module Entropy
    @values = Familia::Set.new name.to_s.downcase.gsub('::', Familia.delim).to_sym, :db => 11
    class << self
      attr_reader :values
      def count
        values.size
      end
      def empty?
        count.zero?
      end
      def pop
        values.pop ||
        [caller[0], rand].gibbler.shorten(12) # TODO: replace this stub
      end
      def generate count=nil
        count ||= 10_000
        stack = caller
        values.redis.pipelined do
          newvalues = (0...count).to_a.collect do |idx|
            val = [OT.instance, stack, OT.now.to_f, idx].gibbler.shorten(12)
            values.add val
          end
        end
      end
    end
  end
end
require 'onetime/models/metadata'
require 'onetime/models/secret'
require 'onetime/models/session'
require 'onetime/models/customer'

__END__

module Onetime
    
  class Metadata < Storable
    include Familia
    include Gibbler::Complex
    prefix :metadata
    index :key
    field :key
    field :custid
    field :state
    field :secret_key
    field :passphrase
    field :viewed => Integer
    field :shared => Integer
    include Familia::Stamps
    attr_reader :entropy
    attr_accessor :passphrase_temp
    gibbler :custid, :secret_key, :entropy
    ttl 7.days
    def initialize custid=nil, entropy=nil
      @custid, @entropy, @state = custid, entropy, :new
    end
    def age
      @age ||= Time.now.utc.to_i-updated
      @age
    end
    def older_than? seconds
      age > seconds
    end
    def key
      @key ||= gibbler.base(36)
      @key
    end
    def valid?
      exists?
    end
    def viewed!
      # Make sure we don't go from :shared to :viewed
      return if state?(:viewed) || state?(:shared)
      @state = 'viewed'
      @viewed = Time.now.utc.to_i
      save
    end
    def state? guess
      state.to_s == guess.to_s
    end
    def shared!
      @state = 'shared'
      @shared = Time.now.utc.to_i
      @secret_key = nil  # so we don't even know which secret this reffered to.
      save
    end
    def load_secret
      OT::Secret.from_redis secret_key
    end
  end
  
  class Secret < Storable
    include Familia
    include Gibbler::Complex
    prefix :secret
    index :key
    field :key
    field :custid
    field :value
    field :value_checksum
    field :state
    field :original_size
    field :size
    field :passphrase
    field :metadata_key
    field :value_encryption => Integer
    field :passphrase_encryption => Integer
    field :viewed => Integer
    field :shared => Integer
    include Familia::Stamps
    attr_reader :entropy
    attr_accessor :passphrase_temp
    gibbler :custid, :passphrase_temp, :value_checksum, :entropy
    ttl 7.days
    def initialize custid=nil, entropy=nil
      @custid, @entropy, @state = custid, entropy, :new
    end
    def customer?
      ! custid.nil?
    end
    def size
      value.to_s.size
    end
    def long
      original_size >= 5000
    end
    def age
      @age ||= Time.now.utc.to_i-updated
      @age
    end
    def older_than? seconds
      age > seconds
    end
    def key
      @key ||= gibbler.base(36)
      @key
    end
    def valid?
      exists? && !value.to_s.empty?
    end
    def encrypt_value v, opts={}
      @value_encryption = 1
      opts.merge! :key => encryption_key 
      @value = v.encrypt opts
      @value_checksum = v.gibbler
    end
    def can_decrypt?
      passphrase.to_s.empty? || !passphrase_temp.to_s.empty?
    end
    def decrypted_value opts={}
      case value_encryption.to_i
      when 0
        self.value
      when 1
        opts.merge! :key => encryption_key
        self.value.decrypt opts
      else
        raise RuntimeError, "Unknown encryption"
      end
    end
    def encryption_key
      OT::Secret.encryption_key self.key, self.passphrase_temp
    end
    def update_passphrase v
      @passphrase_encryption = 1
      @passphrase_temp = v
      @passphrase = BCrypt::Password.create(v, :cost => 10).to_s
    end
    def has_passphrase?
      !passphrase.to_s.empty?
    end
    def passphrase? guess
      begin 
        ret = !has_passphrase? || BCrypt::Password.new(@passphrase) == guess
        @passphrase_temp = guess if ret  # used to decrypt the value
        ret
      rescue BCrypt::Errors::InvalidHash => ex
        msg = "[old-passphrase]"
        !has_passphrase? || (!guess.to_s.empty? && passphrase.to_s.downcase.strip == guess.to_s.downcase.strip)
      end
    end
    def load_metadata
      OT::Metadata.from_redis metadata_key
    end
    def state? guess
      state.to_s == guess.to_s
    end
    def shared!
      @state = 'shared'
      @shared = Time.now.utc.to_i
      save
    end
    def viewed!
      # Make sure we don't go from :shared to :viewed
      return if state?(:viewed) || state?(:shared)
      @state = 'viewed'
      @viewed = Time.now.utc.to_i
      load_metadata.shared!  # update the private key
      destroy!               # delete this shared key
    end
    def self.spawn_pair custid, entropy
      entropy = [entropy, Time.now.to_f * $$].flatten
      metadata, secret = OT::Metadata.new(custid, entropy), OT::Secret.new(custid, entropy)
      metadata.secret_key, secret.metadata_key = secret.key, metadata.key
      [metadata, secret]
    end
    def self.encryption_key *entropy
      #entropy.unshift Gibbler.secret     # If we change this the values are fucked.
      Digest::SHA256.hexdigest(entropy.flatten.compact.join(':'))   # So don't use gibbler here either.
    end
  end
end